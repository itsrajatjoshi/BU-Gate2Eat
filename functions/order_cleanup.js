/**
 * YummBU — Order Retention & Cleanup Service
 * Server-side scheduled 45-day retention enforcement for Firestore orders.
 *
 * Invariants:
 * 1. Safe 45-day retention policy:
 *    - KEEP orders <= 45 days old.
 *    - DELETE orders > 45 days old (strictly terminal statuses only).
 * 2. Active order protection:
 *    - NEVER delete active orders ('placed', 'accepted'), regardless of age.
 * 3. Terminal status requirement:
 *    - Only delete orders in terminal states: 'delivered', 'cancelled', 'rejected', 'delivery_expired'.
 * 4. Missing / malformed timestamp protection:
 *    - If timestamp cannot be parsed, NEVER delete the order (protect data).
 * 5. Future timestamp protection:
 *    - Future timestamps (clock skew) are preserved.
 * 6. Batch safety:
 *    - Chunk batch deletes into <= 400 operations (strictly below Firestore 500 limit).
 * 7. Idempotency:
 *    - Repeated runs produce zero side effects and succeed cleanly.
 * 8. Error isolation:
 *    - A failure in one batch does not crash the entire process.
 */

const RETENTION_DAYS = 45;
const RETENTION_MS = RETENTION_DAYS * 24 * 60 * 60 * 1000; // 3,888,000,000 ms

const ACTIVE_STATUSES = new Set(["placed", "accepted"]);
const TERMINAL_STATUSES = new Set([
  "delivered",
  "cancelled",
  "rejected",
  "delivery_expired",
]);

/**
 * Normalizes any supported timestamp representation into epoch milliseconds.
 * Returns null if the value is missing, empty, invalid, or malformed.
 */
function extractTimestampMillis(raw) {
  if (raw == null) return null;

  // Firestore Timestamp instance (Admin SDK or Client SDK)
  if (typeof raw.toMillis === "function") {
    try {
      const ms = raw.toMillis();
      return typeof ms === "number" && !isNaN(ms) ? ms : null;
    } catch (_) {
      return null;
    }
  }

  // Firestore Timestamp with _seconds / seconds property
  if (typeof raw._seconds === "number") {
    return raw._seconds * 1000 + Math.floor((raw._nanoseconds || 0) / 1e6);
  }
  if (typeof raw.seconds === "number") {
    return raw.seconds * 1000 + Math.floor((raw.nanoseconds || 0) / 1e6);
  }

  // JavaScript Date instance
  if (raw instanceof Date) {
    const time = raw.getTime();
    return isNaN(time) ? null : time;
  }

  // Millisecond integer or number
  if (typeof raw === "number") {
    return !isNaN(raw) && isFinite(raw) && raw > 0 ? Math.floor(raw) : null;
  }

  // String (ISO-8601 or date string)
  if (typeof raw === "string") {
    const trimmed = raw.trim();
    if (!trimmed) return null;
    const parsed = Date.parse(trimmed);
    return isNaN(parsed) ? null : parsed;
  }

  return null;
}

/**
 * Evaluates whether an individual order document is eligible for 45-day cleanup.
 *
 * @param {Object} orderData - Document data from Firestore.
 * @param {number} nowMillis - Current time in milliseconds.
 * @returns {{ shouldDelete: boolean, reason: string, ageMs: number|null }}
 */
function evaluateOrderRetention(orderData, nowMillis = Date.now()) {
  if (!orderData) {
    return { shouldDelete: false, reason: "missing_order_data", ageMs: null };
  }

  const rawStatus = (orderData.status || "").toString().trim().toLowerCase();

  // Invariant 2: Active orders MUST NEVER be deleted
  if (ACTIVE_STATUSES.has(rawStatus)) {
    return {
      shouldDelete: false,
      reason: `active_order_preserved (${rawStatus})`,
      ageMs: null,
    };
  }

  // Invariant 3: Only delete verified terminal statuses
  if (!TERMINAL_STATUSES.has(rawStatus)) {
    return {
      shouldDelete: false,
      reason: `non_terminal_or_unknown_status (${rawStatus || "empty"})`,
      ageMs: null,
    };
  }

  // Invariant 4: Extract and validate createdAt timestamp
  const createdAtMillis = extractTimestampMillis(orderData.createdAt);
  if (createdAtMillis === null) {
    // Missing or corrupt timestamp: NEVER delete, fail safe!
    return {
      shouldDelete: false,
      reason: "malformed_or_missing_timestamp",
      ageMs: null,
    };
  }

  // Invariant 5: Future timestamp protection
  if (createdAtMillis > nowMillis) {
    return {
      shouldDelete: false,
      reason: "future_timestamp_preserved",
      ageMs: nowMillis - createdAtMillis,
    };
  }

  const ageMs = nowMillis - createdAtMillis;

  // Invariant 1:
  // KEEP orders <= 45 days old (ageMs <= RETENTION_MS)
  // DELETE orders > 45 days old (ageMs > RETENTION_MS)
  if (ageMs <= RETENTION_MS) {
    return {
      shouldDelete: false,
      reason: "within_45_day_retention_window",
      ageMs,
    };
  }

  return {
    shouldDelete: true,
    reason: "expired_terminal_order (>45 days)",
    ageMs,
  };
}

/**
 * Executes server-side cleanup of orders older than 45 days.
 *
 * @param {Object} db - Firestore database instance.
 * @param {Object} [options]
 * @param {number} [options.now] - Current time in epoch ms (default: Date.now()).
 * @param {number} [options.batchSize] - Batch chunk size (default: 400, max: 500).
 * @param {number} [options.maxDocsToScan] - Safety cap per run (default: 2000).
 * @param {boolean} [options.dryRun] - Report only, do not commit deletes (default: false).
 * @returns {Promise<Object>} Execution summary report.
 */
async function cleanupOldOrders(db, options = {}) {
  const now = typeof options.now === "number" ? options.now : Date.now();
  const batchSize = Math.min(Math.max(options.batchSize || 400, 1), 500);
  const maxDocsToScan = options.maxDocsToScan || 2000;
  const dryRun = Boolean(options.dryRun);

  const cutoffMillis = now - RETENTION_MS;
  const cutoffDate = new Date(cutoffMillis);

  console.log(`🧹 [Order Retention] Starting cleanup with cutoff: ${cutoffDate.toISOString()} (dryRun: ${dryRun})`);

  let scanned = 0;
  let deleted = 0;
  let preservedActive = 0;
  let preservedRecent = 0;
  let preservedMalformed = 0;
  let preservedOther = 0;
  let batchesCommitted = 0;
  let batchErrors = 0;

  try {
    // Single-field inequality query on createdAt to identify potential candidates.
    // Querying <= cutoffDate retrieves only orders potentially > 45 days old.
    const snapshot = await db
      .collection("orders")
      .where("createdAt", "<", cutoffDate)
      .limit(maxDocsToScan)
      .get();

    scanned = snapshot.size;

    if (scanned === 0) {
      console.log("ℹ️ [Order Retention] No candidate orders older than 45 days found. Exiting cleanly.");
      return {
        scanned: 0,
        deleted: 0,
        preservedActive: 0,
        preservedRecent: 0,
        preservedMalformed: 0,
        preservedOther: 0,
        batchesCommitted: 0,
        batchErrors: 0,
        cutoffIso: cutoffDate.toISOString(),
        dryRun,
      };
    }

    const docsToDelete = [];

    snapshot.forEach((doc) => {
      const data = doc.data();
      const evaluation = evaluateOrderRetention(data, now);

      if (evaluation.shouldDelete) {
        docsToDelete.push(doc);
      } else {
        if (evaluation.reason.startsWith("active_order_preserved")) {
          preservedActive++;
        } else if (evaluation.reason === "within_45_day_retention_window") {
          preservedRecent++;
        } else if (evaluation.reason === "malformed_or_missing_timestamp") {
          preservedMalformed++;
        } else {
          preservedOther++;
        }
      }
    });

    console.log(
      `📊 [Order Retention] Scanned: ${scanned}, Candidates to delete: ${docsToDelete.length}, Preserved Active: ${preservedActive}, Preserved Recent: ${preservedRecent}, Preserved Malformed: ${preservedMalformed}`
    );

    if (dryRun || docsToDelete.length === 0) {
      return {
        scanned,
        deleted: dryRun ? 0 : docsToDelete.length,
        candidateCount: docsToDelete.length,
        preservedActive,
        preservedRecent,
        preservedMalformed,
        preservedOther,
        batchesCommitted: 0,
        batchErrors: 0,
        cutoffIso: cutoffDate.toISOString(),
        dryRun,
      };
    }

    // Execute deletions in batches of <= 400
    for (let i = 0; i < docsToDelete.length; i += batchSize) {
      const chunk = docsToDelete.slice(i, i + batchSize);
      const batch = db.batch();

      for (const doc of chunk) {
        batch.delete(doc.reference);
      }

      try {
        await batch.commit();
        batchesCommitted++;
        deleted += chunk.length;
      } catch (err) {
        batchErrors++;
        console.error(`❌ [Order Retention] Batch commit failed at offset ${i}:`, err);
        // Continue to next batch rather than completely halting if a transient batch error occurs
      }
    }

    console.log(
      `✅ [Order Retention] Finished cleanup. Successfully deleted ${deleted} expired orders in ${batchesCommitted} batch(es).`
    );

    return {
      scanned,
      deleted,
      preservedActive,
      preservedRecent,
      preservedMalformed,
      preservedOther,
      batchesCommitted,
      batchErrors,
      cutoffIso: cutoffDate.toISOString(),
      dryRun: false,
    };
  } catch (error) {
    console.error("❌ [Order Retention] Fatal error during cleanup query:", error);
    throw error;
  }
}

module.exports = {
  RETENTION_DAYS,
  RETENTION_MS,
  ACTIVE_STATUSES,
  TERMINAL_STATUSES,
  extractTimestampMillis,
  evaluateOrderRetention,
  cleanupOldOrders,
};
