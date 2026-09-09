/**
 * YummBU — Server-Authoritative Order Expiration Engine (Phase 5.5)
 *
 * Invariants:
 * 1. Server Authority:
 *    - Order expiration and lifecycle deadlines are strictly server-authoritative.
 *    - Correctness does NOT depend on the Flutter client being open, alive, or connected.
 * 2. Placed Acceptance Timeout (20 Minutes):
 *    - Unaccepted orders exceeding acceptDeadline transition atomically to 'rejected'.
 *    - Updates shopStats: appOrders +1, notAccepted +1.
 * 3. Accepted Delivery Timeout (90 Minutes):
 *    - Undelivered accepted orders exceeding deliveryDeadline transition atomically to 'delivery_expired'.
 *    - Updates shopStats: deliveryExpired +1.
 * 4. Terminal State Immutability:
 *    - Orders in terminal states ('delivered', 'rejected', 'cancelled', 'delivery_expired')
 *      can NEVER be expired, resurrected, or modified.
 * 5. Atomic Transaction Execution:
 *    - Every expiration runs inside an atomic Firestore transaction (db.runTransaction).
 *    - Fresh document state is re-read inside the transaction.
 *    - Concurrency with customer cancellation or shopkeeper accept/deliver is serialized safely.
 * 6. Idempotency & Repeated Worker Invariant:
 *    - Consecutive runs produce zero side effects on already expired or active orders.
 *    - Zero timestamp overwrites on repeat executions.
 * 7. Zero Transaction Side Effects:
 *    - No push notifications or external API dispatches execute inside the transaction callback.
 *    - Push notifications fire via the post-commit Firestore document trigger (onOrderStatusUpdated).
 */

const { FieldValue } = require("firebase-admin/firestore");

const ACCEPT_WINDOW_MINUTES = 20;
const ACCEPT_WINDOW_MS = ACCEPT_WINDOW_MINUTES * 60 * 1000; // 1,200,000 ms

const DELIVERY_WINDOW_MINUTES = 90;
const DELIVERY_WINDOW_MS = DELIVERY_WINDOW_MINUTES * 60 * 1000; // 5,400,000 ms

const TERMINAL_STATUSES = new Set([
  "delivered",
  "rejected",
  "cancelled",
  "delivery_expired",
]);

/**
 * Normalizes any supported timestamp representation into epoch milliseconds.
 * Returns null if the value is missing, empty, invalid, out of range, or malformed.
 */
function extractTimestampMillis(raw) {
  if (raw == null) return null;

  // Firestore Timestamp instance (Admin SDK or Client SDK)
  if (typeof raw.toMillis === "function") {
    try {
      const ms = raw.toMillis();
      return typeof ms === "number" && !isNaN(ms) && isFinite(ms) && ms > 0 && ms < 2e14 ? ms : null;
    } catch (_) {
      return null;
    }
  }

  // Firestore Timestamp with _seconds / seconds property
  if (typeof raw._seconds === "number") {
    const s = raw._seconds;
    if (isNaN(s) || !isFinite(s) || s <= 0 || s > 2e11) return null;
    return Math.floor(s * 1000 + Math.floor((raw._nanoseconds || 0) / 1e6));
  }
  if (typeof raw.seconds === "number") {
    const s = raw.seconds;
    if (isNaN(s) || !isFinite(s) || s <= 0 || s > 2e11) return null;
    return Math.floor(s * 1000 + Math.floor((raw.nanoseconds || 0) / 1e6));
  }

  // JavaScript Date instance
  if (raw instanceof Date) {
    const time = raw.getTime();
    return !isNaN(time) && isFinite(time) && time > 0 && time < 2e14 ? time : null;
  }

  // Millisecond or Second integer/number
  if (typeof raw === "number") {
    if (isNaN(raw) || !isFinite(raw) || raw <= 0 || raw >= 2e14) return null;
    // Disambiguate 10-digit Unix timestamp in seconds (e.g. 1.7e9) vs milliseconds (>= 1e11)
    if (raw > 1e9 && raw < 1e11) {
      return Math.floor(raw * 1000);
    }
    if (raw >= 1e11) {
      return Math.floor(raw);
    }
    return null; // Reject unreasonable timestamps (e.g. year 1970 < 1e9)
  }

  // String (ISO-8601 or date string)
  if (typeof raw === "string") {
    const trimmed = raw.trim();
    if (!trimmed) return null;
    const parsed = Date.parse(trimmed);
    if (isNaN(parsed) || !isFinite(parsed) || parsed <= 0 || parsed >= 2e14) return null;
    // Reject dates earlier than year 2020 (1577836800000) to prevent premature expiration on bad strings
    if (parsed < 1577836800000) return null;
    return parsed;
  }

  return null;
}

/**
 * Evaluates whether an order document is eligible for server-authoritative expiration.
 *
 * @param {Object} orderData - Order document data from Firestore.
 * @param {number} [nowMillis=Date.now()] - Server epoch time in milliseconds.
 * @returns {{
 *   eligible: boolean,
 *   type?: 'placed_timeout'|'delivery_timeout',
 *   targetStatus?: string,
 *   reason: string,
 *   deadlineMillis?: number|null
 * }}
 */
function evaluateOrderExpiration(orderData, nowMillis = Date.now()) {
  if (!orderData || typeof orderData !== "object") {
    return { eligible: false, reason: "missing_or_invalid_order_data" };
  }

  const status = (orderData.status || "").toString().trim().toLowerCase();

  // Invariant 4: Terminal orders are strictly immutable
  if (TERMINAL_STATUSES.has(status)) {
    return {
      eligible: false,
      reason: `terminal_status_immutable (${status})`,
    };
  }

  // Case A: Placed order awaiting shopkeeper acceptance
  if (status === "placed") {
    let deadlineMs = extractTimestampMillis(orderData.acceptDeadline);
    if (deadlineMs === null) {
      // Fallback: derive from createdAt + 20 minutes
      const createdMs = extractTimestampMillis(orderData.createdAt);
      if (createdMs !== null) {
        deadlineMs = createdMs + ACCEPT_WINDOW_MS;
      }
    }

    if (deadlineMs === null) {
      return {
        eligible: false,
        reason: "missing_or_malformed_accept_deadline",
      };
    }

    if (nowMillis >= deadlineMs) {
      return {
        eligible: true,
        type: "placed_timeout",
        targetStatus: "rejected",
        reason: "Order was automatically rejected because the shopkeeper did not accept it within 20 minutes.",
        deadlineMillis: deadlineMs,
      };
    }

    return {
      eligible: false,
      reason: "accept_deadline_not_expired",
      deadlineMillis: deadlineMs,
    };
  }

  // Case B: Accepted order in progress awaiting delivery
  if (status === "accepted") {
    let deadlineMs = extractTimestampMillis(orderData.deliveryDeadline);
    if (deadlineMs === null) {
      // Fallback: derive from acceptedAt + 90 minutes
      const acceptedMs = extractTimestampMillis(orderData.acceptedAt);
      if (acceptedMs !== null) {
        deadlineMs = acceptedMs + DELIVERY_WINDOW_MS;
      }
    }

    if (deadlineMs === null) {
      return {
        eligible: false,
        reason: "missing_or_malformed_delivery_deadline",
      };
    }

    if (nowMillis >= deadlineMs) {
      return {
        eligible: true,
        type: "delivery_timeout",
        targetStatus: "delivery_expired",
        reason: "Delivery window of 90 minutes expired.",
        deadlineMillis: deadlineMs,
      };
    }

    return {
      eligible: false,
      reason: "delivery_deadline_not_expired",
      deadlineMillis: deadlineMs,
    };
  }

  return {
    eligible: false,
    reason: `unsupported_status_for_expiration (${status})`,
  };
}

/**
 * Executes an atomic Firestore transaction to expire an individual order.
 * Re-reads the fresh document state inside the transaction to ensure serializability.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} orderId
 * @param {number} [nowMillis=Date.now()]
 * @returns {Promise<{
 *   success: boolean,
 *   orderId: string,
 *   fromStatus?: string,
 *   toStatus?: string,
 *   reason: string
 * }>}
 */
async function expireOrderTransaction(db, orderId, nowMillis = Date.now()) {
  if (!orderId || typeof orderId !== "string") {
    return { success: false, orderId: orderId || "", reason: "invalid_order_id" };
  }

  const orderRef = db.collection("orders").doc(orderId);

  try {
    return await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(orderRef);
      if (!doc.exists) {
        return { success: false, orderId, reason: "order_not_found" };
      }

      const orderData = doc.data() || {};
      const evalResult = evaluateOrderExpiration(orderData, nowMillis);

      if (!evalResult.eligible) {
        return {
          success: false,
          orderId,
          fromStatus: orderData.status,
          reason: evalResult.reason,
        };
      }

      const shopId = orderData.shopId;
      const statsDocRef = shopId ? db.collection("shopStats").doc(shopId) : null;

      if (evalResult.type === "placed_timeout") {
        transaction.update(orderRef, {
          status: "rejected",
          rejectionReason: evalResult.reason,
          rejectedAt: FieldValue.serverTimestamp(),
          autoExpiredAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        if (statsDocRef) {
          transaction.set(
            statsDocRef,
            {
              shopId: shopId,
              appOrders: FieldValue.increment(1),
              notAccepted: FieldValue.increment(1),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }

        return {
          success: true,
          orderId,
          fromStatus: "placed",
          toStatus: "rejected",
          reason: evalResult.reason,
        };
      }

      if (evalResult.type === "delivery_timeout") {
        transaction.update(orderRef, {
          status: "delivery_expired",
          rejectionReason: evalResult.reason,
          deliveryExpiredAt: FieldValue.serverTimestamp(),
          autoExpiredAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        if (statsDocRef) {
          transaction.set(
            statsDocRef,
            {
              shopId: shopId,
              deliveryExpired: FieldValue.increment(1),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }

        return {
          success: true,
          orderId,
          fromStatus: "accepted",
          toStatus: "delivery_expired",
          reason: evalResult.reason,
        };
      }

      return {
        success: false,
        orderId,
        reason: "unknown_expiration_type",
      };
    });
  } catch (err) {
    return {
      success: false,
      orderId,
      reason: `transaction_error: ${err.message}`,
    };
  }
}

/**
 * Sweeps active orders ('placed' and 'accepted') and triggers transactional expiration
 * for any order whose authoritative deadline has expired.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {Object} [options={}]
 * @param {number} [options.nowMillis] - Custom time for deterministic testing.
 * @param {number} [options.limit=50] - Maximum orders to process per batch.
 * @param {boolean} [options.dryRun=false] - If true, evaluates without modifying database.
 * @returns {Promise<{
 *   scannedCount: number,
 *   expiredPlaced: number,
 *   expiredAccepted: number,
 *   totalExpired: number,
 *   skippedCount: number,
 *   dryRun: boolean,
 *   errors: string[]
 * }>}
 */
async function expireStaleOrders(db, options = {}) {
  const nowMillis = typeof options.nowMillis === "number" ? options.nowMillis : Date.now();
  const batchLimit = typeof options.limit === "number" ? Math.min(options.limit, 100) : 50;
  const dryRun = options.dryRun === true;

  const summary = {
    scannedCount: 0,
    expiredPlaced: 0,
    expiredAccepted: 0,
    totalExpired: 0,
    skippedCount: 0,
    dryRun,
    errors: [],
  };

  try {
    // 1. Query placed orders (strictly active) with bounded cursor pagination to eliminate starvation
    let lastPlacedDoc = null;
    let placedPages = 0;
    const MAX_PAGES = 5; // Scans up to 500 active orders per cycle across pages

    while (placedPages < MAX_PAGES) {
      let query = db.collection("orders").where("status", "==", "placed").limit(batchLimit);
      if (lastPlacedDoc && typeof query.startAfter === "function") {
        query = query.startAfter(lastPlacedDoc);
      }
      const placedSnapshot = await query.get();
      if (!placedSnapshot || placedSnapshot.empty || !placedSnapshot.docs || placedSnapshot.docs.length === 0) {
        break;
      }

      for (const doc of placedSnapshot.docs) {
        summary.scannedCount++;
        const evalResult = evaluateOrderExpiration(doc.data(), nowMillis);

        if (evalResult.eligible && evalResult.type === "placed_timeout") {
          if (dryRun) {
            summary.expiredPlaced++;
            summary.totalExpired++;
          } else {
            const res = await expireOrderTransaction(db, doc.id, nowMillis);
            if (res.success) {
              summary.expiredPlaced++;
              summary.totalExpired++;
            } else {
              summary.skippedCount++;
              if (res.reason && !res.reason.includes("immutable") && !res.reason.includes("not_expired")) {
                summary.errors.push(`Order #${doc.id}: ${res.reason}`);
              }
            }
          }
        } else {
          summary.skippedCount++;
        }
      }

      if (placedSnapshot.docs.length < batchLimit) {
        break; // End of placed collection reached
      }
      lastPlacedDoc = placedSnapshot.docs[placedSnapshot.docs.length - 1];
      placedPages++;
    }

    // 2. Query accepted orders (strictly active) with bounded cursor pagination to eliminate starvation
    let lastAcceptedDoc = null;
    let acceptedPages = 0;

    while (acceptedPages < MAX_PAGES) {
      let query = db.collection("orders").where("status", "==", "accepted").limit(batchLimit);
      if (lastAcceptedDoc && typeof query.startAfter === "function") {
        query = query.startAfter(lastAcceptedDoc);
      }
      const acceptedSnapshot = await query.get();
      if (!acceptedSnapshot || acceptedSnapshot.empty || !acceptedSnapshot.docs || acceptedSnapshot.docs.length === 0) {
        break;
      }

      for (const doc of acceptedSnapshot.docs) {
        summary.scannedCount++;
        const evalResult = evaluateOrderExpiration(doc.data(), nowMillis);

        if (evalResult.eligible && evalResult.type === "delivery_timeout") {
          if (dryRun) {
            summary.expiredAccepted++;
            summary.totalExpired++;
          } else {
            const res = await expireOrderTransaction(db, doc.id, nowMillis);
            if (res.success) {
              summary.expiredAccepted++;
              summary.totalExpired++;
            } else {
              summary.skippedCount++;
              if (res.reason && !res.reason.includes("immutable") && !res.reason.includes("not_expired")) {
                summary.errors.push(`Order #${doc.id}: ${res.reason}`);
              }
            }
          }
        } else {
          summary.skippedCount++;
        }
      }

      if (acceptedSnapshot.docs.length < batchLimit) {
        break; // End of accepted collection reached
      }
      lastAcceptedDoc = acceptedSnapshot.docs[acceptedSnapshot.docs.length - 1];
      acceptedPages++;
    }
  } catch (err) {
    summary.errors.push(`Sweep error: ${err.message}`);
  }

  return summary;
}

module.exports = {
  ACCEPT_WINDOW_MINUTES,
  ACCEPT_WINDOW_MS,
  DELIVERY_WINDOW_MINUTES,
  DELIVERY_WINDOW_MS,
  TERMINAL_STATUSES,
  extractTimestampMillis,
  evaluateOrderExpiration,
  expireOrderTransaction,
  expireStaleOrders,
};
