/**
 * YummBU — Backend Cloud Functions
 * Production Server-Side FCM Dispatch Engine (1st Gen Cloud Functions)
 * 
 * Invariants:
 * 1. ZERO client-side credentials in Flutter client.
 * 2. Strict role-based isolation (shopkeepers receive shop orders; customers receive only their own order updates).
 * 3. Scoped exclusively to the target customer / target shop.
 * 4. Anonymous tokens are NEVER targeted. Only verified, identified recipients receive notifications.
 * 5. Transition-aware: Only legitimate status changes trigger customer pushes (placed->accepted, placed->rejected, etc.).
 * 6. Metadata/timestamp updates do NOT generate notifications.
 * 7. Pre-accept cancellation deletes the document with ZERO notification.
 * 8. Multi-device support for customer and shopkeeper accounts.
 * 9. Automated cleanup of stale / invalid device tokens.
 * 10. Idempotency guards prevent duplicate dispatches on Cloud Function retries.
 * 11. Notification failure never mutates or reverts order state.
 */

const functions = require("firebase-functions/v1");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// ─── HELPER: Clean Stale Tokens ─────────────────────────────────────────────
async function cleanStaleTokens(tokens, responses) {
  const staleBatch = db.batch();
  let staleCount = 0;

  responses.forEach((resp, idx) => {
    if (!resp.success) {
      const errorCode = resp.error ? resp.error.code : "";
      if (
        errorCode === "messaging/invalid-registration-token" ||
        errorCode === "messaging/registration-token-not-registered" ||
        errorCode === "messaging/mismatched-credential"
      ) {
        const staleToken = tokens[idx];
        if (staleToken && typeof staleToken === "string" && staleToken.trim().length > 0) {
          staleBatch.delete(db.collection("deviceTokens").doc(staleToken.trim()));
          staleCount++;
        }
      }
    }
  });

  if (staleCount > 0) {
    try {
      await staleBatch.commit();
      console.log(`🧹 [FCM Cleanup] Purged ${staleCount} stale/unregistered device token(s).`);
    } catch (cleanErr) {
      console.error("⚠️ [FCM Cleanup] Note on batch deleting stale tokens:", cleanErr);
    }
  }
}

// ─── PART 4: SHOPKEEPER NEW ORDER TRIGGER ───────────────────────────────────
exports.onNewOrderCreated = functions.firestore
  .document("orders/{orderId}")
  .onCreate(async (snapshot, context) => {
    const t2 = Date.now();
    const orderData = snapshot.data();
    if (!orderData) {
      console.log("⚠️ [FCM Dispatch] No snapshot data found for event.");
      return null;
    }

    const orderId = context.params.orderId || orderData.orderId;
    const shopId = orderData.shopId;
    const status = orderData.status;
    const t1 = orderData.createdAt
      ? (typeof orderData.createdAt.toMillis === "function" ? orderData.createdAt.toMillis() : Date.now())
      : Date.now();

    if (!orderId || !shopId) {
      console.log(`⚠️ [FCM Dispatch] Malformed order document missing orderId or shopId: ${orderId}`);
      return null;
    }

    // Idempotency check 1: Check if already notified for this new order
    if (orderData.newOrderNotificationDispatched === true) {
      console.log(`ℹ️ [FCM Shopkeeper] Order #${orderId} already notified. Skipping duplicate execution.`);
      return null;
    }

    // Only dispatch for initial placed in-app orders
    if (status !== "placed") {
      console.log(`ℹ️ [FCM Dispatch] Order #${orderId} status is '${status}'. Skipping new-order push.`);
      return null;
    }

    try {
      const tokensSnapshot = await db
        .collection("deviceTokens")
        .where("role", "==", "shopkeeper")
        .where("shopId", "==", shopId)
        .get();

      const t3 = Date.now();

      if (tokensSnapshot.empty) {
        console.log(`⚠️ [FCM Dispatch] No registered shopkeeper devices found for shop: ${shopId}`);
        return null;
      }

      // Filter tokens strictly requiring non-anonymous verified shopkeeper identity
      const deviceTokens = [];
      tokensSnapshot.forEach((doc) => {
        const data = doc.data();
        if (
          data &&
          data.token &&
          typeof data.token === "string" &&
          data.token.trim().length > 0 &&
          data.role === "shopkeeper" &&
          data.shopId === shopId &&
          data.phone &&
          typeof data.phone === "string" &&
          data.phone.trim().length > 0
        ) {
          const cleanToken = data.token.trim();
          if (!deviceTokens.includes(cleanToken)) {
            deviceTokens.push(cleanToken);
          }
        }
      });

      if (deviceTokens.length === 0) {
        console.log(`⚠️ [FCM Dispatch] No non-anonymous verified shopkeeper device tokens for shop: ${shopId}`);
        return null;
      }

      const itemCount = Array.isArray(orderData.items) ? orderData.items.length : 1;
      const finalBill = orderData.totalAmount != null ? Math.round(orderData.totalAmount) : (orderData.finalBillAmount || 0);

      const multicastMessage = {
        notification: {
          title: "🍔 New Order Received!",
          body: `Order #${orderId} • ₹${finalBill} (${itemCount} ${itemCount === 1 ? "item" : "items"})`,
        },
        data: {
          type: "new_order",
          orderId: String(orderId),
          shopId: String(shopId),
          recipientRole: "shopkeeper",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          ttl: 3600,
          notification: {
            channelId: "yummbu_orders_channel",
            sound: "default",
            priority: "max",
            defaultSound: true,
            defaultVibrateTimings: true,
            visibility: "public",
          },
        },
        tokens: deviceTokens,
      };

      console.log(
        `🚀 [FCM Shopkeeper] Sending New Order notification for #${orderId} to ${deviceTokens.length} device(s) [${shopId}]...`
      );

      const t4 = Date.now();
      const response = await messaging.sendEachForMulticast(multicastMessage);
      const t5 = Date.now();

      console.log(
        `⏱️ [FCM Shopkeeper Timeline] Order #${orderId} | T1(created)=${t1}, T2(funcStart)=${t2}, T3(tokensResolved)=${t3}, T4(sendReq)=${t4}, T5(fcmResp)=${t5} | TriggerLatency=${t2 - t1}ms, TokenLookup=${t3 - t2}ms, FcmSend=${t5 - t4}ms`
      );
      console.log(
        `✅ [FCM Shopkeeper] Results for Order #${orderId}: ${response.successCount} succeeded, ${response.failureCount} failed.`
      );

      // Record idempotency flag on order doc
      try {
        await db.collection("orders").doc(orderId).update({
          newOrderNotificationDispatched: true,
          notifiedShopkeeperCount: response.successCount,
        });
      } catch (_) {}

      if (response.failureCount > 0) {
        await cleanStaleTokens(deviceTokens, response.responses);
      }

      return {
        orderId,
        shopId,
        targetedDevices: deviceTokens.length,
        successCount: response.successCount,
      };
    } catch (error) {
      console.error(`❌ [FCM Shopkeeper] Fatal error dispatching notification for Order #${orderId}:`, error);
      return null;
    }
  });

// ─── PART 5: CUSTOMER ORDER LIFECYCLE TRIGGER ───────────────────────────────
exports.onOrderStatusUpdated = functions.firestore
  .document("orders/{orderId}")
  .onUpdate(async (change, context) => {
    const t2 = Date.now();
    const beforeData = change.before.data();
    const afterData = change.after.data();

    if (!beforeData || !afterData) {
      return null;
    }

    const oldStatus = beforeData.status;
    const newStatus = afterData.status;

    // Invariant 1: Unchanged status (e.g. metadata/timestamp/notes update) -> NO notification
    if (oldStatus === newStatus) {
      return null;
    }

    // Idempotency check 2: Prevent duplicate dispatches if already notified for this newStatus
    if (afterData.lastNotifiedStatus === newStatus) {
      console.log(`ℹ️ [FCM Customer] Status '${newStatus}' already notified for #${afterData.orderId}. Skipping.`);
      return null;
    }

    const orderId = context.params.orderId || afterData.orderId;
    const shopId = afterData.shopId;
    const shopName = afterData.shopName || "Shop";
    const customerId = afterData.customerId;
    const customerPhone = afterData.customerPhone;
    const rejectionReason = afterData.rejectionReason;

    // Invariant 4: Anonymous customer orders MUST NEVER receive customer push notifications
    const isAnonymousCustomer =
      (!customerId || customerId.trim() === "" || customerId.startsWith("cust_anon")) &&
      (!customerPhone || customerPhone.trim() === "");

    if (isAnonymousCustomer) {
      console.log(
        `ℹ️ [FCM Customer] Order #${orderId} belongs to anonymous customer (customerId: ${customerId}, phone: ${customerPhone}). Skipping notification.`
      );
      return null;
    }

    // Invariant 2: Determine valid customer notification transition
    let notificationTitle = "";
    let notificationBody = "";
    let notificationType = "";

    if (oldStatus === "placed" && newStatus === "accepted") {
      notificationType = "order_accepted";
      notificationTitle = "✅ Order Accepted";
      notificationBody = `Your order from ${shopName} has been accepted.`;
    } else if (oldStatus === "placed" && newStatus === "rejected") {
      notificationType = "order_rejected";
      notificationTitle = "❌ Order Not Accepted";
      notificationBody = rejectionReason && rejectionReason.trim().length > 0
        ? `Your order from ${shopName} could not be accepted (${rejectionReason}).`
        : `Your order from ${shopName} could not be accepted.`;
    } else if (oldStatus === "placed" && newStatus === "delivery_expired") {
      // 20-minute auto-reject / acceptance timeout
      notificationType = "order_expired";
      notificationTitle = "⌛ Order Expired";
      notificationBody = `Your order from ${shopName} was not accepted in time.`;
    } else if (oldStatus === "accepted" && newStatus === "rejected") {
      // Post-accept rejection (within 15-minute window)
      notificationType = "order_rejected";
      notificationTitle = "❌ Order Not Completed";
      notificationBody = rejectionReason && rejectionReason.trim().length > 0
        ? `Your order from ${shopName} could not be completed (${rejectionReason}).`
        : `Your order from ${shopName} could not be completed.`;
    } else if (oldStatus === "accepted" && newStatus === "delivered") {
      notificationType = "order_delivered";
      notificationTitle = "🎉 Order Delivered";
      notificationBody = `Your order from ${shopName} has been delivered successfully.`;
    } else if (oldStatus === "accepted" && newStatus === "delivery_expired") {
      // 90-minute delivery expiry
      notificationType = "order_expired";
      notificationTitle = "⚠️ Order Expired";
      notificationBody = `Your order from ${shopName} has expired.`;
    } else {
      // Unrecognized or non-notifiable transition (e.g. cancelled before accept)
      console.log(`ℹ️ [FCM Customer] Non-notifiable transition: ${oldStatus} -> ${newStatus}. Skipping.`);
      return null;
    }

    // Invariant 3: Query target customer device tokens strictly matching customerId or customerPhone
    // Explicitly reject anonymous tokens
    try {
      const customerTokens = new Set();

      // Query by customerId ONLY if valid non-anonymous customerId
      if (customerId && typeof customerId === "string" && !customerId.startsWith("cust_anon")) {
        const idSnap = await db
          .collection("deviceTokens")
          .where("role", "==", "customer")
          .where("customerId", "==", customerId.trim())
          .get();

        idSnap.forEach((doc) => {
          const d = doc.data();
          if (
            d &&
            d.token &&
            typeof d.token === "string" &&
            d.token.trim().length > 0 &&
            d.role === "customer" &&
            d.phone &&
            typeof d.phone === "string" &&
            d.phone.trim().length > 0 &&
            (!d.customerId || !d.customerId.startsWith("cust_anon"))
          ) {
            customerTokens.add(d.token.trim());
          }
        });
      }

      // Query by phone ONLY if valid non-empty phone
      if (customerPhone && typeof customerPhone === "string" && customerPhone.trim().length > 0) {
        const phoneSnap = await db
          .collection("deviceTokens")
          .where("role", "==", "customer")
          .where("phone", "==", customerPhone.trim())
          .get();

        phoneSnap.forEach((doc) => {
          const d = doc.data();
          if (
            d &&
            d.token &&
            typeof d.token === "string" &&
            d.token.trim().length > 0 &&
            d.role === "customer" &&
            d.phone &&
            typeof d.phone === "string" &&
            d.phone.trim().length > 0 &&
            (!d.customerId || !d.customerId.startsWith("cust_anon"))
          ) {
            customerTokens.add(d.token.trim());
          }
        });
      }

      const t3 = Date.now();
      const targetTokens = Array.from(customerTokens);

      if (targetTokens.length === 0) {
        console.log(
          `⚠️ [FCM Customer] No verified non-anonymous customer device tokens found for order #${orderId} (customerId: ${customerId}, phone: ${customerPhone})`
        );
        return null;
      }

      const multicastMessage = {
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        data: {
          type: notificationType,
          orderId: String(orderId),
          shopId: String(shopId || ""),
          recipientRole: "customer",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          ttl: 3600,
          notification: {
            channelId: "yummbu_customer_orders_channel",
            sound: "default",
            priority: "max",
            defaultSound: true,
            defaultVibrateTimings: true,
            visibility: "public",
          },
        },
        tokens: targetTokens,
      };

      console.log(
        `🚀 [FCM Customer] Dispatching '${notificationType}' for #${orderId} to ${targetTokens.length} device(s) [Customer: ${customerPhone || customerId}]...`
      );

      const t4 = Date.now();
      const response = await messaging.sendEachForMulticast(multicastMessage);
      const t5 = Date.now();

      const t1 = beforeData.updatedAt
        ? (typeof beforeData.updatedAt.toMillis === "function" ? beforeData.updatedAt.toMillis() : Date.now())
        : Date.now();

      console.log(
        `⏱️ [FCM Customer Timeline] Order #${orderId} (${notificationType}) | T1(statusChanged)=${t1}, T2(funcStart)=${t2}, T3(tokensResolved)=${t3}, T4(sendReq)=${t4}, T5(fcmResp)=${t5} | TriggerLatency=${t2 - t1}ms, TokenLookup=${t3 - t2}ms, FcmSend=${t5 - t4}ms`
      );
      console.log(
        `✅ [FCM Customer] Results for Order #${orderId} (${notificationType}): ${response.successCount} succeeded, ${response.failureCount} failed.`
      );

      // Record idempotency flag on order doc
      try {
        await db.collection("orders").doc(orderId).update({
          lastNotifiedStatus: newStatus,
          lastNotifiedType: notificationType,
          lastNotifiedAt: FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      if (response.failureCount > 0) {
        await cleanStaleTokens(targetTokens, response.responses);
      }

      return {
        orderId,
        transition: `${oldStatus} -> ${newStatus}`,
        notificationType,
        targetedDevices: targetTokens.length,
        successCount: response.successCount,
      };
    } catch (error) {
      console.error(`❌ [FCM Customer] Error dispatching lifecycle notification for Order #${orderId}:`, error);
      return null;
    }
  });

// ─── PART 5: AUTHENTICATION & ROLE CLAIMS FOUNDATION ────────────────────────
const {
  CANONICAL_ROLES,
  CANONICAL_ACCOUNT_STATUSES,
  buildCanonicalClaims,
  normalizeCanonicalPhone,
  canonicalizeShopId,
  resolveIdentityForPhone,
  createCustomTokenForPhone,
  SERVER_ADMIN_PHONES,
  SERVER_SHOPKEEPER_PHONE_MAP,
} = require("./auth_service");

exports.auth = {
  CANONICAL_ROLES,
  CANONICAL_ACCOUNT_STATUSES,
  buildCanonicalClaims,
  normalizeCanonicalPhone,
  canonicalizeShopId,
  resolveIdentityForPhone,
  createCustomTokenForPhone,
  SERVER_ADMIN_PHONES,
  SERVER_SHOPKEEPER_PHONE_MAP,
};

// ─── PART 6: DATA CLEANUP & STORAGE MANAGEMENT (CHECKPOINT 5) ───────────────
const { getStorage } = require("firebase-admin/storage");
const { cleanupOldOrders } = require("./order_cleanup");
const { auditAndCleanStorageOrphans } = require("./storage_cleanup");

/**
 * Scheduled Cloud Function (Runs daily at 03:00 UTC).
 * Automatically purges terminal orders older than 45 days.
 * Strictly preserves active orders ('placed', 'accepted') and recent orders (<= 45 days).
 */
exports.scheduledOrderCleanup = functions.pubsub
  .schedule("0 3 * * *")
  .timeZone("UTC")
  .onRun(async (context) => {
    console.log("🧹 [Scheduled Cleanup] Starting daily 45-day order retention job...");
    try {
      const summary = await cleanupOldOrders(db);
      console.log("✅ [Scheduled Cleanup] Completed successfully:", JSON.stringify(summary));
      return summary;
    } catch (err) {
      console.error("❌ [Scheduled Cleanup] Error during daily order cleanup:", err);
      throw err;
    }
  });

/**
 * Callable Cloud Function for Admin manual order cleanup or dry-run execution.
 * Restricted strictly to authenticated callers with verified Custom Claim role === 'admin'.
 */
exports.manualOrderCleanup = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication is required to run order cleanup."
    );
  }

  const token = context.auth.token || {};
  if (token.role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only authorized administrators with role 'admin' can run order cleanup."
    );
  }

  const dryRun = data && data.dryRun === true;
  const rawBatchSize = data && typeof data.batchSize === "number" && Number.isInteger(data.batchSize) ? data.batchSize : 400;
  const batchSize = Math.max(1, Math.min(rawBatchSize, 500));
  return await cleanupOldOrders(db, { dryRun, batchSize });
});

/**
 * Callable Cloud Function for Reference-Aware Storage Orphan Audit.
 * Restricted strictly to authenticated callers with verified Custom Claim role === 'admin'.
 * Default is dryRun: true (reports orphans without deleting).
 */
exports.storageOrphanAudit = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication is required to audit storage orphans."
    );
  }

  const token = context.auth.token || {};
  if (token.role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only authorized administrators with role 'admin' can audit storage orphans."
    );
  }

  const bucket = getStorage().bucket();
  const dryRun = data ? data.dryRun !== false : true;
  const rawMinAge = data && typeof data.minAgeHours === "number" && Number.isInteger(data.minAgeHours) ? data.minAgeHours : 24;
  const minAgeHours = Math.max(1, Math.min(rawMinAge, 720));
  return await auditAndCleanStorageOrphans(bucket, db, { dryRun, minAgeHours });
});

exports.dataCleanup = {
  cleanupOldOrders,
  auditAndCleanStorageOrphans,
};

// ─── PART 7: SERVER-AUTHORITATIVE ORDER CREATION (CHECKPOINT 4.1) ───────────
const {
  processServerAuthoritativeOrder,
  buildDeterministicCartKey,
  computeIdempotencyDocId,
  computeRequestFingerprint,
} = require("./order_creation");

/**
 * HTTPS REST / HTTP Trigger for Server-Authoritative Order Creation (Phase 4.1 & 4.4).
 * Requires Authorization: Bearer <FirebaseIdToken>.
 * Rejects unauthenticated callers, forged customerId, invalid shops/items, client price tampering,
 * rate limit abuse, and idempotency conflicts.
 */
exports.createOrder = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed. Use POST." });
  }

  // Verify Firebase ID Token from Authorization header
  let authContext = null;
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith("Bearer ")) {
    const idToken = authHeader.split("Bearer ")[1].trim();
    try {
      const decodedToken = await getAuth().verifyIdToken(idToken);
      authContext = {
        uid: decodedToken.uid,
        token: decodedToken,
        phone: decodedToken.phone_number || "",
      };
    } catch (authErr) {
      return res.status(401).json({ error: "Unauthorized: Invalid or expired authentication token." });
    }
  }

  if (!authContext) {
    return res.status(401).json({ error: "Unauthorized: Missing or invalid Authorization header." });
  }

  try {
    const result = await processServerAuthoritativeOrder(db, authContext, req.body);
    return res.status(200).json(result);
  } catch (err) {
    const statusCode = err.status || (
      err.code === "not-found" ? 404 :
      err.code === "permission-denied" ? 403 :
      err.code === "resource-exhausted" ? 429 :
      err.code === "failed-precondition" ? 409 :
      err.code === "already-exists" ? 409 :
      400
    );
    return res.status(statusCode).json({
      error: err.message || "Failed to create order.",
      code: err.code || "unknown",
    });
  }
});

/**
 * HTTPS Callable Cloud Function for Server-Authoritative Order Creation (Phase 4.1 & 4.4).
 * Authenticated directly via Firebase SDK context.
 */
exports.createOrderCallable = functions.https.onCall(async (data, context) => {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Customer authentication is required to create an order."
    );
  }

  const authContext = {
    uid: context.auth.uid,
    token: context.auth.token,
    phone: context.auth.token.phone_number || "",
  };

  try {
    return await processServerAuthoritativeOrder(db, authContext, data);
  } catch (err) {
    const httpsErrorCode = err.code === "not-found"
      ? "not-found"
      : (err.code === "permission-denied"
        ? "permission-denied"
        : (err.code === "failed-precondition" || err.code === "already-exists"
          ? "failed-precondition"
          : (err.code === "resource-exhausted"
            ? "resource-exhausted"
            : (err.code === "unauthenticated"
              ? "unauthenticated"
              : "invalid-argument"))));
    throw new functions.https.HttpsError(httpsErrorCode, err.message);
  }
});

exports.orderService = {
  processServerAuthoritativeOrder,
  buildDeterministicCartKey,
  computeIdempotencyDocId,
  computeRequestFingerprint,
};

// ─── PART 8: SERVER-AUTHORITATIVE ORDER EXPIRATION & LIFECYCLE (PHASE 5.5) ──
const {
  expireStaleOrders,
  evaluateOrderExpiration,
  expireOrderTransaction,
  ACCEPT_WINDOW_MINUTES,
  ACCEPT_WINDOW_MS,
  DELIVERY_WINDOW_MINUTES,
  DELIVERY_WINDOW_MS,
} = require("./order_expiration");

/**
 * Scheduled Cloud Function (Runs every 2 minutes).
 * Evaluates active orders and executes server-authoritative expiration
 * for placed orders exceeding 20m accept deadline and accepted orders exceeding 90m delivery deadline.
 */
exports.scheduledOrderExpiration = functions.pubsub
  .schedule("every 2 minutes")
  .onRun(async (context) => {
    console.log("⏱️ [Scheduled Expiration] Starting order expiration sweep...");
    try {
      const summary = await expireStaleOrders(db);
      console.log("✅ [Scheduled Expiration] Completed successfully:", JSON.stringify(summary));
      return summary;
    } catch (err) {
      console.error("❌ [Scheduled Expiration] Error during order expiration:", err);
      throw err;
    }
  });

/**
 * Callable Cloud Function for Admin manual expiration sweep or test verification.
 * Restricted strictly to authenticated callers with verified Custom Claim role === 'admin'.
 */
exports.expireOrdersCallable = functions.https.onCall(async (data, context) => {
  // 1. Mandatory authentication check: Anonymous/unauthenticated callers strictly denied
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication is required to trigger order expiration sweep."
    );
  }

  // 2. Authoritative RBAC check: Caller MUST possess canonical custom claim role == 'admin'
  // Strictly rejects token.admin boolean, phone-number matching, or client-supplied role flags
  const token = context.auth.token || {};
  if (token.role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only authorized administrators with role 'admin' can trigger order expiration sweep."
    );
  }

  // 3. Strict parameter sanitization and bounds enforcement:
  // - limit must be an integer strictly bounded between 1 and 100 (default: 50)
  // - dryRun must be a strict boolean
  // - Arbitrary fields (admin, role, phone, orderId, shopId, status, timestamps) are completely ignored
  const rawLimit = data && typeof data.limit === "number" && Number.isInteger(data.limit) ? data.limit : 50;
  const limit = Math.max(1, Math.min(rawLimit, 100));
  const dryRun = data && data.dryRun === true;

  return await expireStaleOrders(db, { dryRun, limit });
});

exports.orderExpiration = {
  expireStaleOrders,
  evaluateOrderExpiration,
  expireOrderTransaction,
  ACCEPT_WINDOW_MINUTES,
  ACCEPT_WINDOW_MS,
  DELIVERY_WINDOW_MINUTES,
  DELIVERY_WINDOW_MS,
};
