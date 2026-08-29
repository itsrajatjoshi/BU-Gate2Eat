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
