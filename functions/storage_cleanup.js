/**
 * YummBU — Reference-Aware Firebase Storage Orphan Cleanup & Retention Engine
 * Phase 6.5: Storage Orphan Cleanup / Retention / Scheduled Sweeper (Production Hardened)
 *
 * Core Security Model & Invariants:
 * 1. NEVER delete an object merely because it looks old.
 * 2. NEVER delete an object that is actively referenced by live Firestore catalog data:
 *    - shops/{shopId}.bannerUrl, shops/{shopId}.logoUrl, shops/{shopId}.shopLogoImageUrl
 *    - shops/{shopId}/menuItems/{itemId}.imageUrl
 *    - shops/{shopId}/categories/{categoryId}.imageUrl
 * 3. NEVER delete an object referenced by historical order snapshots within the 45-day retention policy:
 *    - orders/{orderId}.items[].imageUrl (active orders + orders <= 45 days old)
 * 4. NEVER bypass the Phase 6.4 retirement invariant:
 *    - Retired/pending assets remain permanently non-reactivable.
 *    - Reconciles physical deletion for existing Phase 6.4 deletionIntents safely without clearing intent records.
 * 5. Multi-Predicate Evaluation Model:
 *    - Explicitly evaluates hasActiveCatalogReference, hasHistoricalReference, insideUploadGrace,
 *      insideOrphanMinAge, hasPendingLifecycleIntent, isRetired.
 *    - Decides: PROTECTED_ACTIVE, PROTECTED_HISTORICAL, PROTECTED_GRACE, PROTECTED_ORPHAN_AGE,
 *      PROTECTED_LIFECYCLE, ELIGIBLE, DELETED, FAILED_RETRY, PRESERVED_CONCURRENT_REFERENCE.
 * 6. Immediate Pre-Delete Re-Verification:
 *    - Re-reads live Firestore references immediately before physical Storage deletion to catch concurrent writes.
 * 7. Sweeper Overlap & Distributed Concurrency Protection:
 *    - Deterministic per-object leases in `_storageCleanupLeases/{sha256Id}` with expiration timestamps.
 *    - Run coordination in `_storageCleanupRuns/{runId}` with heartbeat tracking.
 * 8. Persistent Retry:
 *    - Deletion failures persist failure state to lease documents for safe retry in subsequent sweeps.
 * 9. Bounded Pagination on BOTH Storage and Firestore:
 *    - Storage lists via maxResults and page tokens.
 *    - Firestore scans have safety bounds. Exceeding bounds fails closed (SCAN_BOUND_EXCEEDED).
 * 10. Dry-Run First:
 *     - Full non-destructive dry-run support reporting all candidate counts and reasons.
 * 11. Server-Side Only:
 *     - No client permissions or manipulation capabilities.
 */

const crypto = require('crypto');
const {
  extractStoragePath,
  parseStorageCatalogPath,
  deriveLifecycleDocId,
  isAssetRetired,
  checkActiveFirestoreReference,
  CATALOG_FOLDERS,
} = require('./storage_reference_lifecycle');
const { extractTimestampMillis } = require('./order_cleanup');

// ─── CONFIGURATION & RETENTION CONSTANTS ─────────────────────────────────────
const UPLOAD_GRACE_PERIOD_MS = 2 * 60 * 60 * 1000; // 2 hours: protects in-flight uploads during form editing
const DEFAULT_ORPHAN_MIN_AGE_HOURS = 24; // 24 hours: default minimum age before unreferenced asset is eligible
const DEFAULT_ORPHAN_MIN_AGE_MS = DEFAULT_ORPHAN_MIN_AGE_HOURS * 60 * 60 * 1000;
const ORDER_RETENTION_DAYS = 45; // Aligned with established 45-day order retention policy
const ORDER_RETENTION_MS = ORDER_RETENTION_DAYS * 24 * 60 * 60 * 1000;

// ─── BOUNDED SAFETY CAPS (FAIL-CLOSED BOUNDS) ────────────────────────────────
const MAX_STORAGE_PAGE_SIZE = 100;
const MAX_STORAGE_PAGES_PER_RUN = 10; // Max 1,000 Storage objects inspected per sweep run
const MAX_OBJECTS_PER_RUN = 500;
const MAX_FIRESTORE_REFERENCE_SCAN = 1000;
const MAX_HISTORICAL_ORDER_SCAN = 1000;
const MAX_DELETE_OPERATIONS_PER_RUN = 100;
const LEASE_DURATION_MS = 5 * 60 * 1000; // 5-minute worker lease
const STALE_RUN_HEARTBEAT_MS = 15 * 60 * 1000; // 15-minute run timeout

// ─── DECISION STATES & REASONS ───────────────────────────────────────────────
const DECISION = {
  PROTECTED_ACTIVE: 'PROTECTED_ACTIVE',
  PROTECTED_HISTORICAL: 'PROTECTED_HISTORICAL',
  PROTECTED_GRACE: 'PROTECTED_GRACE',
  PROTECTED_ORPHAN_AGE: 'PROTECTED_ORPHAN_AGE',
  PROTECTED_LIFECYCLE: 'PROTECTED_LIFECYCLE',
  PROTECTED_METADATA: 'PROTECTED_METADATA',
  ELIGIBLE: 'ELIGIBLE',
  DELETED: 'DELETED',
  FAILED_RETRY: 'FAILED_RETRY',
  PRESERVED_CONCURRENT_REFERENCE: 'PRESERVED_CONCURRENT_REFERENCE',
  SKIPPED_ACTIVE_LEASE: 'SKIPPED_ACTIVE_LEASE',
};

const REASON = {
  ACTIVE_CATALOG_REFERENCE: 'ACTIVE_CATALOG_REFERENCE',
  HISTORICAL_ORDER_REFERENCE: 'HISTORICAL_ORDER_REFERENCE',
  UPLOAD_GRACE_PERIOD: 'UPLOAD_GRACE_PERIOD',
  ORPHAN_MIN_AGE: 'ORPHAN_MIN_AGE',
  PENDING_LIFECYCLE: 'PENDING_LIFECYCLE',
  RETIRED_LIFECYCLE: 'RETIRED_LIFECYCLE',
  FAILED_RETIRED_LIFECYCLE: 'FAILED_RETIRED_LIFECYCLE',
  COMPLETED_LIFECYCLE: 'COMPLETED_LIFECYCLE',
  INVALID_CATALOG_PATH: 'INVALID_CATALOG_PATH',
  REFERENCE_SCAN_BOUND_EXCEEDED: 'REFERENCE_SCAN_BOUND_EXCEEDED',
  MALFORMED_METADATA: 'MALFORMED_METADATA',
  MISSING_OR_INVALID_TIMECREATED: 'MISSING_OR_INVALID_TIMECREATED',
  FUTURE_TIMECREATED_ANOMALY: 'FUTURE_TIMECREATED_ANOMALY',
  UNREFERENCED_ORPHAN: 'UNREFERENCED_ORPHAN',
  STALE_LEASE_OWNER_REJECTED: 'STALE_LEASE_OWNER_REJECTED',
};

/**
 * Normalizes any URL, gs:// URI, or relative path to a single canonical storage path.
 * Backward compatibility wrapper delegating to Phase 6.4 canonicalization.
 */
function extractStoragePathFromUrl(url) {
  return extractStoragePath(url);
}

/**
 * Derives a deterministic SHA-256 lease key for an object's canonical path.
 */
function deriveLeaseKey(canonicalPath) {
  return crypto.createHash('sha256').update(canonicalPath || '').digest('hex');
}

/**
 * Gathers all referenced Storage paths across Firestore catalog and historical orders.
 * Bounded with safety caps: if any collection exceeds configured scan bounds, fails closed.
 *
 * @param {Object} db - Firestore Admin SDK database instance.
 * @param {Object} [options]
 * @param {number} [options.now] - Current epoch millis in UTC.
 * @returns {Promise<{ activeCatalogPaths: Set<string>, historicalOrderPaths: Set<string>, boundExceeded: boolean, error?: string }>}
 */
async function collectAuthoritativeReferences(db, options = {}) {
  const now = typeof options.now === 'number' ? options.now : Date.now();
  const activeCatalogPaths = new Set();
  const historicalOrderPaths = new Set();

  function record(url, set) {
    const path = extractStoragePath(url);
    if (path) {
      set.add(path);
    }
  }

  // 1. Scan `shops`
  const shopsQuery = typeof db.collection('shops').limit === 'function'
    ? db.collection('shops').limit(MAX_FIRESTORE_REFERENCE_SCAN + 1)
    : db.collection('shops');
  const shopsSnapshot = await shopsQuery.get();

  if (shopsSnapshot.docs && shopsSnapshot.docs.length > MAX_FIRESTORE_REFERENCE_SCAN) {
    console.error('🚫 [Storage Cleanup] shops collection exceeds safe reference scan bound!');
    return { activeCatalogPaths, historicalOrderPaths, boundExceeded: true, error: REASON.REFERENCE_SCAN_BOUND_EXCEEDED };
  }

  for (const shopDoc of (shopsSnapshot.docs || [])) {
    const data = shopDoc.data() || {};
    record(data.bannerUrl, activeCatalogPaths);
    record(data.logoUrl, activeCatalogPaths);
    record(data.shopLogoImageUrl, activeCatalogPaths);
    record(data.imageUrl, activeCatalogPaths);

    // Scan `menuItems` subcollection
    const menuColl = shopDoc.ref.collection('menuItems');
    const menuQuery = typeof menuColl.limit === 'function'
      ? menuColl.limit(MAX_FIRESTORE_REFERENCE_SCAN + 1)
      : menuColl;
    const menuSnapshot = await menuQuery.get();

    if (menuSnapshot.docs && menuSnapshot.docs.length > MAX_FIRESTORE_REFERENCE_SCAN) {
      console.error(`🚫 [Storage Cleanup] menuItems collection for shop ${shopDoc.id} exceeds safe scan bound!`);
      return { activeCatalogPaths, historicalOrderPaths, boundExceeded: true, error: REASON.REFERENCE_SCAN_BOUND_EXCEEDED };
    }

    for (const itemDoc of (menuSnapshot.docs || [])) {
      const itemData = itemDoc.data() || {};
      record(itemData.imageUrl, activeCatalogPaths);
    }

    // Scan `categories` subcollection
    const catColl = shopDoc.ref.collection('categories');
    const catQuery = typeof catColl.limit === 'function'
      ? catColl.limit(MAX_FIRESTORE_REFERENCE_SCAN + 1)
      : catColl;
    const catSnapshot = await catQuery.get();

    if (catSnapshot.docs && catSnapshot.docs.length > MAX_FIRESTORE_REFERENCE_SCAN) {
      console.error(`🚫 [Storage Cleanup] categories collection for shop ${shopDoc.id} exceeds safe scan bound!`);
      return { activeCatalogPaths, historicalOrderPaths, boundExceeded: true, error: REASON.REFERENCE_SCAN_BOUND_EXCEEDED };
    }

    for (const catDoc of (catSnapshot.docs || [])) {
      const catData = catDoc.data() || {};
      record(catData.imageUrl, activeCatalogPaths);
    }
  }

  // 2. Scan `orders` (historical snapshots within 45-day retention policy)
  // Protected:
  // A. Missing or malformed timestamp -> FAIL CLOSED: protect data!
  // B. Orders created within last 45 days (now - ORDER_RETENTION_MS)
  // C. Active orders ('placed', 'accepted') regardless of age
  const ordersColl = db.collection('orders');
  const ordersQuery = typeof ordersColl.limit === 'function'
    ? ordersColl.limit(MAX_HISTORICAL_ORDER_SCAN + 1)
    : ordersColl;
  const ordersSnapshot = await ordersQuery.get();

  if (ordersSnapshot.docs && ordersSnapshot.docs.length > MAX_HISTORICAL_ORDER_SCAN) {
    console.error('🚫 [Storage Cleanup] orders collection exceeds safe reference scan bound!');
    return { activeCatalogPaths, historicalOrderPaths, boundExceeded: true, error: REASON.REFERENCE_SCAN_BOUND_EXCEEDED };
  }

  for (const orderDoc of (ordersSnapshot.docs || [])) {
    const orderData = orderDoc.data() || {};
    const createdAt = extractTimestampMillis(orderData.createdAt);
    // Invariant: Missing or malformed timestamps must NEVER accidentally make an object eligible (Fail Closed)
    const isWithinRetention = createdAt == null || createdAt >= (now - ORDER_RETENTION_MS);
    const isActive = orderData.status === 'placed' || orderData.status === 'accepted';
    if (isWithinRetention || isActive) {
      if (Array.isArray(orderData.items)) {
        for (const item of orderData.items) {
          if (item && item.imageUrl) {
            record(item.imageUrl, historicalOrderPaths);
          }
        }
      }
    }
  }

  return { activeCatalogPaths, historicalOrderPaths, boundExceeded: false };
}

/**
 * Evaluates a Storage file candidate using explicit evaluation predicates.
 *
 * @param {Object} fileMetadata - { name, timeCreated, updated }
 * @param {Object} references - { activeCatalogPaths, historicalOrderPaths, boundExceeded }
 * @param {Object} options - { now, minAgeHours, db }
 * @returns {Promise<{ eligible: boolean, decision: string, reason: string, parsedPath?: Object, ageMs?: number }>}
 */
async function evaluateCandidateEligibility(fileMetadata, references, options = {}) {
  const now = typeof options.now === 'number' ? options.now : Date.now();
  const minAgeHours = typeof options.minAgeHours === 'number' ? options.minAgeHours : DEFAULT_ORPHAN_MIN_AGE_HOURS;
  const orphanMinAgeMs = minAgeHours * 60 * 60 * 1000;
  const db = options.db;

  const fileName = fileMetadata.name || '';
  const canonicalPath = extractStoragePath(fileName) || fileName;
  const parsed = parseStorageCatalogPath(canonicalPath);

  // 1. Path validity: Only valid catalog paths in approved folders are inspected
  if (!parsed.valid) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_LIFECYCLE,
      reason: REASON.INVALID_CATALOG_PATH,
    };
  }

  // 2. Reference scan bound check: Fail closed if reference scan was incomplete
  if (references.boundExceeded) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_ACTIVE,
      reason: REASON.REFERENCE_SCAN_BOUND_EXCEEDED,
      parsedPath: parsed,
    };
  }

  // 3. Metadata and Creation Timestamp extraction: Authoritatively require metadata.timeCreated
  if (!fileMetadata || fileMetadata.timeCreated == null) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_METADATA,
      reason: REASON.MISSING_OR_INVALID_TIMECREATED,
      parsedPath: parsed,
    };
  }

  const createdTime = extractTimestampMillis(fileMetadata.timeCreated);
  if (createdTime == null) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_METADATA,
      reason: REASON.MALFORMED_METADATA,
      parsedPath: parsed,
    };
  }

  // Future timestamp / clock-skew anomaly: fail closed
  if (createdTime > now) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_METADATA,
      reason: REASON.FUTURE_TIMECREATED_ANOMALY,
      parsedPath: parsed,
      ageMs: now - createdTime,
    };
  }

  const ageMs = now - createdTime;

  // 4. Predicate Evaluation
  const hasActiveCatalogReference = references.activeCatalogPaths.has(canonicalPath);
  const hasHistoricalReference = references.historicalOrderPaths.has(canonicalPath);
  const insideUploadGrace = ageMs < UPLOAD_GRACE_PERIOD_MS;
  const insideOrphanMinAge = ageMs < orphanMinAgeMs;

  // Precedence 1: ACTIVE catalog reference ALWAYS wins -> NEVER delete!
  if (hasActiveCatalogReference) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_ACTIVE,
      reason: REASON.ACTIVE_CATALOG_REFERENCE,
      parsedPath: parsed,
      ageMs,
    };
  }

  // Precedence 2: HISTORICAL order snapshot within retention ALWAYS wins -> NEVER delete!
  if (hasHistoricalReference) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_HISTORICAL,
      reason: REASON.HISTORICAL_ORDER_REFERENCE,
      parsedPath: parsed,
      ageMs,
    };
  }

  // Precedence 3: Upload Grace Period (< 2 hours) -> NEVER delete!
  if (insideUploadGrace) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_GRACE,
      reason: REASON.UPLOAD_GRACE_PERIOD,
      parsedPath: parsed,
      ageMs,
    };
  }

  // Precedence 4: Phase 6.4 Lifecycle Intent Inspection
  if (db) {
    const lifecycleDocId = deriveLifecycleDocId(parsed.folder, parsed.fileName);
    const intentDocRef = db.collection('shops').doc(parsed.shopId)
      .collection('deletionIntents').doc(lifecycleDocId);

    if (typeof intentDocRef.get === 'function') {
      const snap = await intentDocRef.get();
      if (snap.exists) {
        const intentData = snap.data() || {};
        const status = intentData.status;

        // If explicitly retired or pending by authorized shopkeeper/admin in Phase 6.4:
        if (status === 'RETIRED' || status === 'PENDING_DELETION') {
          return {
            eligible: true,
            isLifecycleReconciliation: true,
            lifecycleDocId,
            decision: DECISION.ELIGIBLE,
            reason: REASON.RETIRED_LIFECYCLE,
            parsedPath: parsed,
            ageMs,
          };
        }

        if (status === 'FAILED_RETIRED') {
          return {
            eligible: true,
            isLifecycleReconciliation: true,
            lifecycleDocId,
            decision: DECISION.ELIGIBLE,
            reason: REASON.FAILED_RETIRED_LIFECYCLE,
            parsedPath: parsed,
            ageMs,
          };
        }

        if (status === 'COMPLETED' || status === 'ALREADY_ABSENT') {
          return {
            eligible: true,
            isLifecycleReconciliation: true,
            lifecycleDocId,
            decision: DECISION.ELIGIBLE,
            reason: REASON.COMPLETED_LIFECYCLE,
            parsedPath: parsed,
            ageMs,
          };
        }

        if (status === 'ABORTED_REFERENCED' || status === 'IN_PROGRESS') {
          return {
            eligible: false,
            decision: DECISION.PROTECTED_LIFECYCLE,
            reason: REASON.PENDING_LIFECYCLE,
            parsedPath: parsed,
            ageMs,
          };
        }
      }
    }
  }

  // Precedence 5: Orphan Minimum Age (< 24h) for unreferenced objects WITHOUT lifecycle intent
  if (insideOrphanMinAge) {
    return {
      eligible: false,
      decision: DECISION.PROTECTED_ORPHAN_AGE,
      reason: REASON.ORPHAN_MIN_AGE,
      parsedPath: parsed,
      ageMs,
    };
  }

  // Precedence 6: Genuine Unreferenced Orphan (age >= 24h, no references, no lifecycle intent)
  return {
    eligible: true,
    isLifecycleReconciliation: false,
    decision: DECISION.ELIGIBLE,
    reason: REASON.UNREFERENCED_ORPHAN,
    parsedPath: parsed,
    ageMs,
  };
}

/**
 * Checks whether an image is referenced in historical orders within the 45-day retention policy
 * or in active orders.
 * Fails closed if the scan limit is exceeded or if timestamp is missing/malformed.
 *
 * @param {Object} db - Firestore database instance.
 * @param {Object} parsedPath - { shopId, folder, fileName, fullPath }
 * @param {Object} [options] - { now }
 * @returns {Promise<{ isReferenced: boolean, referenceType?: string, orderId?: string, orderStatus?: string, createdAt?: any, strategy?: string, message?: string }>}
 */
async function checkHistoricalOrderReference(db, parsedPath, options = {}) {
  if (!db) return { isReferenced: false };
  const now = typeof options.now === 'number' ? options.now : Date.now();
  const ordersColl = db.collection('orders');
  if (typeof ordersColl.limit !== 'function') return { isReferenced: false };

  const query = ordersColl.limit(MAX_HISTORICAL_ORDER_SCAN + 1);
  const snap = await query.get();

  if (snap.docs && snap.docs.length > MAX_HISTORICAL_ORDER_SCAN) {
    // Fail closed: order scan limit exceeded!
    return {
      isReferenced: true,
      referenceType: 'SCAN_BOUND_EXCEEDED',
      strategy: 'FAIL_CLOSED_BOUND_EXCEEDED',
      message: 'Orders collection exceeds safe pre-delete verification limit.',
    };
  }

  const targetFileName = parsedPath.fileName;
  const targetFullPath = parsedPath.fullPath;

  for (const doc of (snap.docs || [])) {
    const data = doc.data() || {};
    const createdAt = extractTimestampMillis(data.createdAt);
    // Invariant: Missing or malformed timestamps must fail closed (treat as within retention)
    const isWithinRetention = createdAt == null || createdAt >= (now - ORDER_RETENTION_MS);
    const isActive = data.status === 'placed' || data.status === 'accepted';

    if (isWithinRetention || isActive) {
      if (Array.isArray(data.items)) {
        for (const item of data.items) {
          if (item && item.imageUrl) {
            const img = String(item.imageUrl);
            if (img.includes(targetFileName) || img.includes(targetFullPath)) {
              return {
                isReferenced: true,
                referenceType: 'HISTORICAL_ORDER_REFERENCE',
                orderId: doc.id,
                orderStatus: data.status,
                createdAt: data.createdAt,
              };
            }
          }
        }
      }
    }
  }

  return { isReferenced: false };
}

/**
 * Critical Final Pre-Delete Re-Verification:
 * Immediately before calling file.delete(), re-reads live Firestore reference state
 * for this exact object to catch any concurrent pointer updates occurring between discovery and execution.
 * Re-verifies both active catalog references and historical order references (fail closed).
 *
 * @param {Object} db - Firestore instance.
 * @param {Object} parsedPath - { shopId, folder, fileName, fullPath }
 * @param {Object} [options] - { now }
 * @returns {Promise<{ safe: boolean, reason?: string, details?: Object }>}
 */
async function immediatePreDeleteVerification(db, parsedPath, options = {}) {
  if (!db) return { safe: true };

  // 1. Re-check active catalog references
  const refCheck = await checkActiveFirestoreReference(
    db,
    parsedPath.shopId,
    parsedPath.folder,
    parsedPath.fileName
  );

  if (refCheck.isReferenced) {
    return {
      safe: false,
      reason: DECISION.PRESERVED_CONCURRENT_REFERENCE,
      details: refCheck,
    };
  }

  // 2. Re-check historical order references (Fail-Closed, 45-day retention + active order protection)
  const histCheck = await checkHistoricalOrderReference(db, parsedPath, options);
  if (histCheck.isReferenced) {
    return {
      safe: false,
      reason: DECISION.PRESERVED_CONCURRENT_REFERENCE,
      details: histCheck,
    };
  }

  return { safe: true };
}

/**
 * Acquires a deterministic candidate lease in Firestore with a unique fencing token and generation.
 * Prevents overlapping sweeper workers from operating on the same object, and protects against
 * stale worker execution via generational fencing tokens.
 *
 * @param {Object} db - Firestore instance.
 * @param {string} canonicalPath - Normalized storage path.
 * @param {string} runId - Identifier of current sweeper execution run.
 * @param {number} now - Epoch millis in UTC.
 * @returns {Promise<{ acquired: boolean, leaseDocRef?: Object, leaseToken?: string, generation?: number, reason?: string }>}
 */
async function acquireCandidateLease(db, canonicalPath, runId, now) {
  if (!db) return { acquired: true, leaseToken: 'mock_token', generation: 1 };

  const leaseKey = deriveLeaseKey(canonicalPath);
  const leaseRef = db.collection('_storageCleanupLeases').doc(leaseKey);

  if (typeof leaseRef.get !== 'function' || typeof leaseRef.set !== 'function') {
    return { acquired: true, leaseToken: 'mock_token', generation: 1, leaseDocRef: leaseRef };
  }

  const snap = await leaseRef.get();
  let prevGeneration = 0;
  let prevRetryCount = 0;

  if (snap.exists) {
    const data = snap.data() || {};
    prevGeneration = typeof data.generation === 'number' ? data.generation : 0;
    prevRetryCount = typeof data.retryCount === 'number' ? data.retryCount : 0;

    // Reject if active unexpired lease held by another run
    if (data.status === 'IN_PROGRESS' && data.leaseExpiresAt > now && data.claimedByRunId !== runId) {
      return { acquired: false, reason: 'LEASE_ACTIVE_ANOTHER_WORKER' };
    }
  }

  const generation = prevGeneration + 1;
  const leaseToken = crypto.randomBytes(16).toString('hex');
  const leaseExpiresAt = now + LEASE_DURATION_MS;

  await leaseRef.set({
    canonicalPath,
    claimedByRunId: runId,
    leaseToken,
    generation,
    status: 'IN_PROGRESS',
    leaseExpiresAt,
    acquiredAt: new Date(now).toISOString(),
    updatedAt: new Date(now).toISOString(),
    retryCount: prevRetryCount,
  }, { merge: true });

  return {
    acquired: true,
    leaseDocRef: leaseRef,
    leaseToken,
    generation,
    leaseExpiresAt,
  };
}

/**
 * Fencing Validation Gate:
 * Verifies that the worker still holds authoritative ownership of the candidate lease.
 * A stale worker whose lease expired or was superseded by a newer generation will FAIL CLOSED.
 */
async function verifyCandidateLeaseOwnership(db, canonicalPath, leaseToken, generation, now = Date.now()) {
  if (!db) return { valid: true };

  const leaseKey = deriveLeaseKey(canonicalPath);
  const leaseRef = db.collection('_storageCleanupLeases').doc(leaseKey);

  if (typeof leaseRef.get !== 'function') return { valid: true };

  const snap = await leaseRef.get();
  if (!snap.exists) {
    return { valid: false, reason: 'LEASE_NOT_FOUND' };
  }

  const data = snap.data() || {};
  if (data.leaseToken !== leaseToken || data.generation !== generation) {
    return {
      valid: false,
      reason: REASON.STALE_LEASE_OWNER_REJECTED,
      message: `Fencing Token Mismatch: Current generation ${data.generation} does not match worker generation ${generation}`,
    };
  }

  if (data.status !== 'IN_PROGRESS') {
    return { valid: false, reason: 'LEASE_NOT_IN_PROGRESS' };
  }

  if (data.leaseExpiresAt < now) {
    return { valid: false, reason: 'LEASE_EXPIRED' };
  }

  return { valid: true, data };
}

/**
 * Renews candidate lease heartbeat authoritatively checking fencing token.
 */
async function renewCandidateLeaseHeartbeat(db, canonicalPath, leaseToken, generation, now = Date.now()) {
  if (!db) return { renewed: true };
  const check = await verifyCandidateLeaseOwnership(db, canonicalPath, leaseToken, generation, now);
  if (!check.valid) {
    return { renewed: false, reason: check.reason };
  }

  const leaseKey = deriveLeaseKey(canonicalPath);
  const leaseRef = db.collection('_storageCleanupLeases').doc(leaseKey);
  await leaseRef.set({
    leaseExpiresAt: now + LEASE_DURATION_MS,
    heartbeatAt: new Date(now).toISOString(),
  }, { merge: true });

  return { renewed: true };
}

/**
 * Finalizes candidate lease only if the worker still owns the current lease generation and token.
 */
async function finalizeCandidateLease(dbOrRef, canonicalPathOrStatus, leaseTokenOrDetails, generation, status, details = {}, now = Date.now()) {
  if (!dbOrRef) return { finalized: true };

  // Support legacy/direct docRef call: finalizeCandidateLease(leaseDocRef, status, details)
  if (typeof dbOrRef.set === 'function') {
    const statusVal = canonicalPathOrStatus;
    const detailsVal = leaseTokenOrDetails || {};
    await dbOrRef.set({
      status: statusVal,
      ...detailsVal,
      finalizedAt: new Date().toISOString(),
    }, { merge: true });
    return { finalized: true };
  }

  const db = dbOrRef;
  const canonicalPath = canonicalPathOrStatus;
  const leaseToken = leaseTokenOrDetails;

  const leaseKey = deriveLeaseKey(canonicalPath);
  const leaseRef = db.collection('_storageCleanupLeases').doc(leaseKey);
  if (typeof leaseRef.get !== 'function' || typeof leaseRef.set !== 'function') return { finalized: true };

  // Fencing check: verify ownership before mutating
  const ownership = await verifyCandidateLeaseOwnership(db, canonicalPath, leaseToken, generation, now);
  if (!ownership.valid) {
    console.error(`🚫 [Lease Fencing] Finalize rejected for stale worker: ${ownership.reason}`);
    return { finalized: false, reason: ownership.reason };
  }

  await leaseRef.set({
    status,
    ...details,
    finalizedAt: new Date(now).toISOString(),
  }, { merge: true });

  return { finalized: true };
}

/**
 * Records candidate failure with retry counter increment, strictly verifying fencing token.
 */
async function recordCandidateFailure(db, canonicalPath, leaseToken, generation, error, now = Date.now()) {
  if (!db) return { recorded: false };

  const leaseKey = deriveLeaseKey(canonicalPath);
  const leaseRef = db.collection('_storageCleanupLeases').doc(leaseKey);
  if (typeof leaseRef.get !== 'function' || typeof leaseRef.set !== 'function') return { recorded: false };

  // Fencing check: verify ownership before updating failure
  const snap = await leaseRef.get();
  if (snap.exists) {
    const data = snap.data() || {};
    if (data.leaseToken !== leaseToken || data.generation !== generation) {
      console.error(`🚫 [Lease Fencing] Failure recording rejected for stale worker: generation/token mismatch.`);
      return { recorded: false, reason: REASON.STALE_LEASE_OWNER_REJECTED };
    }

    await leaseRef.set({
      status: DECISION.FAILED_RETRY,
      lastError: error ? (error.message || error.toString()) : 'UNKNOWN_ERROR',
      retryCount: (data.retryCount || 0) + 1,
      failedAt: new Date(now).toISOString(),
    }, { merge: true });
    return { recorded: true };
  }

  return { recorded: false };
}

/**
 * Coordinates sweeper run to detect and safely manage overlapping scheduled function executions.
 *
 * @param {Object} db - Firestore instance.
 * @param {string} runId - Unique run identifier.
 * @param {number} now - Current time millis.
 * @returns {Promise<{ proceed: boolean, reason?: string, runDocRef?: Object }>}
 */
async function coordinateSweeperRun(db, runId, now) {
  if (!db) return { proceed: true };
  const runsColl = db.collection('_storageCleanupRuns');
  if (typeof runsColl.doc !== 'function') return { proceed: true };

  const runDocRef = runsColl.doc(runId);
  const lockDocRef = runsColl.doc('active_sweeper_lock');

  if (typeof lockDocRef.get === 'function') {
    const lockSnap = await lockDocRef.get();
    if (lockSnap.exists) {
      const lockData = lockSnap.data() || {};
      const lastHeartbeat = lockData.heartbeat || 0;
      if (lockData.status === 'RUNNING' && (now - lastHeartbeat) < STALE_RUN_HEARTBEAT_MS) {
        return {
          proceed: false,
          reason: 'ACTIVE_SWEEPER_OVERLAP_PREVENTED',
          message: `Sweeper run skipped: Active sweeper "${lockData.runId}" is already running with recent heartbeat.`,
        };
      }
    }

    await lockDocRef.set({
      runId,
      status: 'RUNNING',
      startedAt: now,
      heartbeat: now,
    });
  }

  if (typeof runDocRef.set === 'function') {
    await runDocRef.set({
      runId,
      status: 'RUNNING',
      startedAt: now,
      heartbeat: now,
    });
  }

  return { proceed: true, runDocRef, lockDocRef };
}

/**
 * Executes a comprehensive, reference-aware orphan cleanup sweep across Cloud Storage catalog assets.
 *
 * @param {Object} bucket - Firebase Storage / Google Cloud Storage bucket instance.
 * @param {Object} db - Firestore instance.
 * @param {Object} [options]
 * @param {boolean} [options.dryRun] - Defaults to true for safety unless explicitly false.
 * @param {number} [options.minAgeHours] - Defaults to 24 hours.
 * @param {number} [options.batchSize] - Max physical deletes per run (default: 50, max: 100).
 * @param {number} [options.now] - Epoch millis in UTC (default Date.now()).
 * @returns {Promise<Object>} Structured sweep report.
 */
async function sweepStorageOrphans(bucket, db, options = {}) {
  const dryRun = options.dryRun !== false; // Defaults to true
  const minAgeHours = typeof options.minAgeHours === 'number' ? options.minAgeHours : DEFAULT_ORPHAN_MIN_AGE_HOURS;
  const rawBatchSize = typeof options.batchSize === 'number' ? options.batchSize : 50;
  const batchSize = Math.max(1, Math.min(rawBatchSize, MAX_DELETE_OPERATIONS_PER_RUN));
  const now = typeof options.now === 'number' ? options.now : Date.now();
  const runId = `sweep_${now}_${Math.random().toString(36).substring(2, 8)}`;

  console.log(`🧹 [Storage Sweeper] Starting run "${runId}" (dryRun: ${dryRun}, minAgeHours: ${minAgeHours}, maxBatch: ${batchSize})...`);

  // 1. Sweeper Concurrency Coordination
  const coordination = await coordinateSweeperRun(db, runId, now);
  if (!coordination.proceed) {
    console.log(`ℹ️ [Storage Sweeper] ${coordination.message}`);
    return {
      runId,
      status: 'SKIPPED',
      reason: coordination.reason,
      message: coordination.message,
      dryRun,
    };
  }

  // 2. Authoritative Reference Discovery (Bounded)
  const references = await collectAuthoritativeReferences(db, { now });

  // 3. Storage Object Enumeration (Bounded Pagination)
  let pageCount = 0;
  let totalScanned = 0;
  let pageToken = null;
  const counts = {
    totalScanned: 0,
    protectedActive: 0,
    protectedHistorical: 0,
    protectedGrace: 0,
    protectedOrphanAge: 0,
    protectedLifecycle: 0,
    eligible: 0,
    deleted: 0,
    failedRetry: 0,
    preservedConcurrent: 0,
    skippedLease: 0,
  };
  const reasonsBreakdown = {};
  const candidatesForDeletion = [];

  function recordReason(reason) {
    reasonsBreakdown[reason] = (reasonsBreakdown[reason] || 0) + 1;
  }

  if (bucket && typeof bucket.getFiles === 'function') {
    do {
      pageCount++;
      const queryOptions = {
        prefix: 'shops/',
        maxResults: MAX_STORAGE_PAGE_SIZE,
        autoPaginate: false,
      };
      if (pageToken) queryOptions.pageToken = pageToken;

      const [files, nextQuery] = await bucket.getFiles(queryOptions);
      pageToken = nextQuery && nextQuery.pageToken;

      for (const file of (files || [])) {
        totalScanned++;
        counts.totalScanned++;

        const metadata = file.metadata || {};
        const fileMetadata = {
          name: file.name,
          timeCreated: metadata.timeCreated,
          updated: metadata.updated,
        };

        const evalResult = await evaluateCandidateEligibility(fileMetadata, references, {
          now,
          minAgeHours,
          db,
        });

        recordReason(evalResult.reason);

        if (!evalResult.eligible) {
          if (evalResult.decision === DECISION.PROTECTED_ACTIVE) counts.protectedActive++;
          else if (evalResult.decision === DECISION.PROTECTED_HISTORICAL) counts.protectedHistorical++;
          else if (evalResult.decision === DECISION.PROTECTED_GRACE) counts.protectedGrace++;
          else if (evalResult.decision === DECISION.PROTECTED_ORPHAN_AGE) counts.protectedOrphanAge++;
          else if (evalResult.decision === DECISION.PROTECTED_LIFECYCLE) counts.protectedLifecycle++;
          continue;
        }

        counts.eligible++;
        candidatesForDeletion.push({
          file,
          evalResult,
        });

        if (!dryRun && candidatesForDeletion.length >= batchSize) break;
      }

      if ((!dryRun && candidatesForDeletion.length >= batchSize) || totalScanned >= MAX_OBJECTS_PER_RUN) {
        break;
      }
    } while (pageToken && pageCount < MAX_STORAGE_PAGES_PER_RUN);
  }

  console.log(
    `📊 [Storage Sweeper Discovery] Scanned: ${counts.totalScanned}, Active: ${counts.protectedActive}, Historical: ${counts.protectedHistorical}, Grace: ${counts.protectedGrace}, OrphanAge: ${counts.protectedOrphanAge}, Lifecycle: ${counts.protectedLifecycle}, Eligible: ${counts.eligible}`
  );

  // 4. Execution Phase (Immediate Pre-Delete Gate + Lease Acquisition)
  if (!dryRun && candidatesForDeletion.length > 0) {
    console.log(`🗑️ [Storage Sweeper Execution] Processing ${candidatesForDeletion.length} candidates for physical purge...`);

    for (const candidate of candidatesForDeletion) {
      const { file, evalResult } = candidate;
      const { parsedPath } = evalResult;

      // A. Candidate Lease Acquisition (Concurrency & Fencing Safety)
      const leaseResult = await acquireCandidateLease(db, parsedPath.fullPath, runId, now);
      if (!leaseResult.acquired) {
        counts.skippedLease++;
        recordReason('SKIPPED_ACTIVE_LEASE');
        continue;
      }
      const { leaseToken, generation } = leaseResult;

      // B. Immediate Pre-Delete Verification (Reduces discovery-to-delete window)
      const preCheck = await immediatePreDeleteVerification(db, parsedPath, { now });
      if (!preCheck.safe) {
        counts.preservedConcurrent++;
        const reasonKey = (preCheck.details && preCheck.details.referenceType === 'HISTORICAL_ORDER_REFERENCE')
          ? REASON.HISTORICAL_ORDER_REFERENCE
          : REASON.ACTIVE_CATALOG_REFERENCE;
        recordReason(reasonKey);

        // If candidate had an existing deletion intent, update its status to ABORTED_REFERENCED
        const lifecycleDocId = evalResult.lifecycleDocId || deriveLifecycleDocId(parsedPath.folder, parsedPath.fileName);
        if (db) {
          const intentRef = db.collection('shops').doc(parsedPath.shopId)
            .collection('deletionIntents').doc(lifecycleDocId);
          if (typeof intentRef.get === 'function' && typeof intentRef.set === 'function') {
            const snap = await intentRef.get();
            if (snap.exists) {
              await intentRef.set({
                status: 'ABORTED_REFERENCED',
                abortedAt: new Date(now).toISOString(),
                referenceDetails: preCheck.details,
              }, { merge: true });
            }
          }
        }

        await finalizeCandidateLease(db, parsedPath.fullPath, leaseToken, generation, DECISION.PRESERVED_CONCURRENT_REFERENCE, {
          reason: preCheck.reason,
          details: preCheck.details,
        }, now);
        continue;
      }

      // C. Fencing Gate Verification before any destructive action
      const fencingCheck = await verifyCandidateLeaseOwnership(db, parsedPath.fullPath, leaseToken, generation, now);
      if (!fencingCheck.valid) {
        console.error(`🚫 [Sweeper] Stale worker aborted delete: ${fencingCheck.reason}`);
        counts.skippedLease++;
        recordReason(REASON.STALE_LEASE_OWNER_REJECTED);
        continue;
      }

      // D. Phase 6.4 Pre-Delete Intent Retirement Lock
      // Commit RETIRED state in Firestore BEFORE physical delete so that
      // any concurrent client write attempting to reactivate this asset
      // will be strictly rejected by assertAssetActivatable()
      const lifecycleDocId = evalResult.lifecycleDocId || deriveLifecycleDocId(parsedPath.folder, parsedPath.fileName);
      if (db) {
        const intentRef = db.collection('shops').doc(parsedPath.shopId)
          .collection('deletionIntents').doc(lifecycleDocId);
        if (typeof intentRef.set === 'function') {
          let existingData = {};
          if (typeof intentRef.get === 'function') {
            const snap = await intentRef.get();
            if (snap.exists) {
              existingData = snap.data() || {};
            }
          }
          await intentRef.set({
            canonicalPath: parsedPath.fullPath,
            folder: parsedPath.folder,
            fileName: parsedPath.fileName,
            status: 'RETIRED',
            retiredAt: existingData.retiredAt || new Date(now).toISOString(),
            requestedBy: existingData.requestedBy || 'Phase6.5_Sweeper',
            sweeperRunId: runId,
          }, { merge: true });
        }
      }

      // E. Physical Cloud Storage Deletion
      try {
        if (typeof file.delete === 'function') {
          await file.delete();
        }
        counts.deleted++;

        // Finalize Phase 6.4 Lifecycle Intent to COMPLETED
        if (db) {
          const intentRef = db.collection('shops').doc(parsedPath.shopId)
            .collection('deletionIntents').doc(lifecycleDocId);
          if (typeof intentRef.set === 'function') {
            await intentRef.set({
              status: 'COMPLETED',
              completedAt: new Date().toISOString(),
              purgedBySweeperRun: runId,
            }, { merge: true });
          }
        }

        await finalizeCandidateLease(db, parsedPath.fullPath, leaseToken, generation, DECISION.DELETED, {
          purgedAt: new Date().toISOString(),
        }, now);
      } catch (err) {
        const isNotFound = err.code === 404 ||
          err.code === 'NOT_FOUND' ||
          (err.message && err.message.includes('No such object'));

        if (isNotFound) {
          // Idempotent safe outcome: object was already removed
          counts.deleted++;
          if (db) {
            const intentRef = db.collection('shops').doc(parsedPath.shopId)
              .collection('deletionIntents').doc(lifecycleDocId);
            if (typeof intentRef.set === 'function') {
              await intentRef.set({
                status: 'COMPLETED',
                alreadyAbsent: true,
                completedAt: new Date().toISOString(),
                purgedBySweeperRun: runId,
              }, { merge: true });
            }
          }
          await finalizeCandidateLease(db, parsedPath.fullPath, leaseToken, generation, DECISION.DELETED, {
            alreadyAbsent: true,
            purgedAt: new Date().toISOString(),
          }, now);
        } else {
          // Transient failure: persist failure state to lease with fencing validation
          counts.failedRetry++;
          recordReason('STORAGE_DELETE_FAILURE');
          console.error(`⚠️ [Storage Sweeper] Failed to delete candidate "${file.name}":`, err);
          await recordCandidateFailure(db, parsedPath.fullPath, leaseToken, generation, err, now);
        }
      }
    }
  }

  // 5. Finalize Sweeper Run Document
  if (coordination.runDocRef && typeof coordination.runDocRef.set === 'function') {
    await coordination.runDocRef.set({
      status: 'COMPLETED',
      completedAt: Date.now(),
      counts,
      reasons: reasonsBreakdown,
      dryRun,
    }, { merge: true });
  }

  if (coordination.lockDocRef && typeof coordination.lockDocRef.set === 'function') {
    let stillOwnsLock = true;
    if (typeof coordination.lockDocRef.get === 'function') {
      const lockSnap = await coordination.lockDocRef.get();
      if (lockSnap.exists) {
        const lockData = lockSnap.data() || {};
        if (lockData.runId && lockData.runId !== runId) {
          stillOwnsLock = false;
          console.warn(`⚠️ [Storage Sweeper] Run lock ownership lost to "${lockData.runId}". Skipping lock release.`);
        }
      }
    }
    if (stillOwnsLock) {
      await coordination.lockDocRef.set({
        status: 'IDLE',
        completedAt: Date.now(),
        lastCompletedRunId: runId,
      }, { merge: true });
    }
  }

  return {
    runId,
    status: 'COMPLETED',
    dryRun,
    minAgeHours,
    batchSize,
    counts,
    reasons: reasonsBreakdown,
    boundExceeded: references.boundExceeded,
  };
}

/**
 * Backward compatibility alias for existing callers.
 */
async function auditAndCleanStorageOrphans(bucket, db, options = {}) {
  return await sweepStorageOrphans(bucket, db, options);
}

module.exports = {
  UPLOAD_GRACE_PERIOD_MS,
  DEFAULT_ORPHAN_MIN_AGE_HOURS,
  DEFAULT_ORPHAN_MIN_AGE_MS,
  ORDER_RETENTION_DAYS,
  ORDER_RETENTION_MS,
  MAX_STORAGE_PAGE_SIZE,
  MAX_STORAGE_PAGES_PER_RUN,
  MAX_OBJECTS_PER_RUN,
  MAX_FIRESTORE_REFERENCE_SCAN,
  MAX_HISTORICAL_ORDER_SCAN,
  MAX_DELETE_OPERATIONS_PER_RUN,
  LEASE_DURATION_MS,
  STALE_RUN_HEARTBEAT_MS,
  DECISION,
  REASON,
  extractStoragePathFromUrl,
  deriveLeaseKey,
  collectAuthoritativeReferences,
  evaluateCandidateEligibility,
  checkHistoricalOrderReference,
  immediatePreDeleteVerification,
  acquireCandidateLease,
  verifyCandidateLeaseOwnership,
  renewCandidateLeaseHeartbeat,
  finalizeCandidateLease,
  recordCandidateFailure,
  coordinateSweeperRun,
  sweepStorageOrphans,
  auditAndCleanStorageOrphans,
};
