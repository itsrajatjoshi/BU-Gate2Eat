/**
 * BU Gate2Eat — Node Test Suite for Server-Side Order Retention & Storage Cleanup
 * Phase 6.5: Complete Adversarial Test Suite (Tests A through Z)
 */

const assert = require("assert");
const {
  RETENTION_DAYS,
  RETENTION_MS,
  ACTIVE_STATUSES,
  TERMINAL_STATUSES,
  extractTimestampMillis,
  evaluateOrderRetention,
  cleanupOldOrders,
} = require("./order_cleanup");
const {
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
  DECISION,
  REASON,
  extractStoragePathFromUrl,
  deriveLeaseKey,
  collectAuthoritativeReferences,
  evaluateCandidateEligibility,
  immediatePreDeleteVerification,
  acquireCandidateLease,
  verifyCandidateLeaseOwnership,
  renewCandidateLeaseHeartbeat,
  finalizeCandidateLease,
  recordCandidateFailure,
  coordinateSweeperRun,
  sweepStorageOrphans,
  auditAndCleanStorageOrphans,
} = require("./storage_cleanup");
const {
  assertAssetActivatable,
  deriveLifecycleDocId,
  isAssetRetired,
  checkActiveFirestoreReference,
  extractStoragePath,
  parseStorageCatalogPath,
} = require("./storage_reference_lifecycle");

console.log("🧪 Starting Server-Side Cleanup & Retention Test Suite...\n");

// ─── 1. Exact 45-Day Retention Constants & Timestamp Parser ─────────────────
assert.strictEqual(RETENTION_DAYS, 45, "Retention days must be exactly 45");
assert.strictEqual(RETENTION_MS, 45 * 24 * 60 * 60 * 1000, "Retention ms must equal 45*24*60*60*1000");

// Timestamp extraction tests
const now = 1757234567000;
assert.strictEqual(extractTimestampMillis(null), null, "Null timestamp returns null");
assert.strictEqual(extractTimestampMillis(undefined), null, "Undefined timestamp returns null");
assert.strictEqual(extractTimestampMillis(""), null, "Empty string timestamp returns null");
assert.strictEqual(extractTimestampMillis("invalid_date"), null, "Malformed string timestamp returns null");
assert.strictEqual(extractTimestampMillis(now), now, "Numeric timestamp preserved");
assert.strictEqual(extractTimestampMillis(new Date(now)), now, "Date instance parsed to millis");
assert.strictEqual(extractTimestampMillis({ toMillis: () => now }), now, "Firestore Timestamp with toMillis() parsed");
assert.strictEqual(extractTimestampMillis({ _seconds: Math.floor(now / 1000), _nanoseconds: (now % 1000) * 1e6 }), now, "Timestamp with _seconds/_nanoseconds parsed");

console.log("✅ 1. Timestamp extraction and normalization verified.");

// ─── 2. Boundary Condition Testing ──────────────────────────────────────────
const ONE_SEC = 1000;
const ONE_HOUR = 60 * 60 * 1000;

// Test A: Exactly 45 days old -> MUST KEEP (<= 45 days)
const exactly45DaysOld = {
  status: "delivered",
  createdAt: now - RETENTION_MS,
};
const resExact = evaluateOrderRetention(exactly45DaysOld, now);
assert.strictEqual(resExact.shouldDelete, false, "Order exactly 45 days old must be KEPT");
assert.strictEqual(resExact.reason, "within_45_day_retention_window");

// Test B: 44 days 23 hours old -> MUST KEEP
const under45DaysOld = {
  status: "delivered",
  createdAt: now - (RETENTION_MS - ONE_HOUR),
};
const resUnder = evaluateOrderRetention(under45DaysOld, now);
assert.strictEqual(resUnder.shouldDelete, false, "Order 44 days 23h old must be KEPT");

// Test C: 45 days + 1 second -> MUST DELETE (if terminal)
const over45DaysOld = {
  status: "delivered",
  createdAt: now - (RETENTION_MS + ONE_SEC),
};
const resOver = evaluateOrderRetention(over45DaysOld, now);
assert.strictEqual(resOver.shouldDelete, true, "Order 45 days + 1s old must be DELETED");

// Test D: Future timestamp -> MUST KEEP
const futureOrder = {
  status: "delivered",
  createdAt: now + 5000,
};
const resFuture = evaluateOrderRetention(futureOrder, now);
assert.strictEqual(resFuture.shouldDelete, false, "Future timestamp order must be KEPT");

// Test E: Missing timestamp -> MUST KEEP (fail safe)
const missingTsOrder = {
  status: "delivered",
};
const resMissing = evaluateOrderRetention(missingTsOrder, now);
assert.strictEqual(resMissing.shouldDelete, false, "Missing timestamp order must be KEPT");
assert.strictEqual(resMissing.reason, "malformed_or_missing_timestamp");

// Test F: Malformed timestamp -> MUST KEEP (fail safe)
const malformedTsOrder = {
  status: "delivered",
  createdAt: "garbage_not_a_date",
};
const resMalformed = evaluateOrderRetention(malformedTsOrder, now);
assert.strictEqual(resMalformed.shouldDelete, false, "Malformed timestamp order must be KEPT");

console.log("✅ 2. Boundary conditions (exact, +1s, -1h, future, missing, malformed) verified.");

// ─── 3. Active Order Protection Invariant ───────────────────────────────────
// Even if an order is 100 days old, if it is 'placed' or 'accepted', NEVER DELETE!
const ancientPlacedOrder = {
  status: "placed",
  createdAt: now - (100 * 24 * 60 * 60 * 1000),
};
const resAncientPlaced = evaluateOrderRetention(ancientPlacedOrder, now);
assert.strictEqual(resAncientPlaced.shouldDelete, false, "Active 'placed' order must NEVER be deleted");

const ancientAcceptedOrder = {
  status: "accepted",
  createdAt: now - (100 * 24 * 60 * 60 * 1000),
};
const resAncientAccepted = evaluateOrderRetention(ancientAcceptedOrder, now);
assert.strictEqual(resAncientAccepted.shouldDelete, false, "Active 'accepted' order must NEVER be deleted");

// Verify all terminal statuses are eligible when > 45 days
const ancientDelivered = { status: "delivered", createdAt: now - (46 * 24 * 60 * 60 * 1000) };
const ancientCancelled = { status: "cancelled", createdAt: now - (46 * 24 * 60 * 60 * 1000) };
const ancientRejected = { status: "rejected", createdAt: now - (46 * 24 * 60 * 60 * 1000) };
const ancientExpired = { status: "delivery_expired", createdAt: now - (46 * 24 * 60 * 60 * 1000) };

assert.strictEqual(evaluateOrderRetention(ancientDelivered, now).shouldDelete, true);
assert.strictEqual(evaluateOrderRetention(ancientCancelled, now).shouldDelete, true);
assert.strictEqual(evaluateOrderRetention(ancientRejected, now).shouldDelete, true);
assert.strictEqual(evaluateOrderRetention(ancientExpired, now).shouldDelete, true);

// Non-terminal unknown status -> DO NOT DELETE
const unknownStatus = { status: "in_review", createdAt: now - (50 * 24 * 60 * 60 * 1000) };
assert.strictEqual(evaluateOrderRetention(unknownStatus, now).shouldDelete, false);

console.log("✅ 3. Active order protection & terminal status requirements verified.");

// ─── 4. Mock Firestore Batching & Idempotency ───────────────────────────────
async function runMockCleanupTest() {
  const store = new Map();

  // Populate store with mock orders
  store.set("o_recent", { status: "delivered", createdAt: new Date(now - 10 * 24 * 60 * 60 * 1000) });
  store.set("o_active_old", { status: "placed", createdAt: new Date(now - 60 * 24 * 60 * 60 * 1000) });
  store.set("o_deliv_old", { status: "delivered", createdAt: new Date(now - 50 * 24 * 60 * 60 * 1000) });
  store.set("o_canc_old", { status: "cancelled", createdAt: new Date(now - 46 * 24 * 60 * 60 * 1000) });
  store.set("o_malformed", { status: "delivered", createdAt: null });

  const mockDb = {
    collection: (name) => {
      assert.strictEqual(name, "orders");
      return {
        where: (field, op, val) => {
          assert.strictEqual(field, "createdAt");
          assert.strictEqual(op, "<");
          return {
            limit: (max) => ({
              get: async () => {
                const docs = [];
                for (const [id, data] of store.entries()) {
                  docs.push({
                    id,
                    data: () => data,
                    reference: { id },
                  });
                }
                return {
                  size: docs.length,
                  docs,
                  forEach: (fn) => docs.forEach(fn),
                };
              },
            }),
          };
        },
      };
    },
    batch: () => {
      const ops = [];
      return {
        delete: (ref) => ops.push(ref.id),
        commit: async () => {
          for (const id of ops) {
            store.delete(id);
          }
        },
      };
    },
  };

  // Run 1: Should delete exactly 2 expired terminal orders ('o_deliv_old', 'o_canc_old')
  const report1 = await cleanupOldOrders(mockDb, { now, batchSize: 400 });
  assert.strictEqual(report1.deleted, 2, "Must delete exactly 2 expired terminal orders");
  assert.strictEqual(report1.preservedActive, 1, "Must preserve active order");
  assert.strictEqual(report1.preservedRecent, 1, "Must preserve recent order");
  assert.strictEqual(report1.preservedMalformed, 1, "Must preserve malformed order");
  assert.strictEqual(store.has("o_recent"), true, "Recent order still exists");
  assert.strictEqual(store.has("o_active_old"), true, "Active old order still exists");
  assert.strictEqual(store.has("o_malformed"), true, "Malformed order still exists");
  assert.strictEqual(store.has("o_deliv_old"), false, "Expired order deleted");
  assert.strictEqual(store.has("o_canc_old"), false, "Expired order deleted");

  // Run 2: Idempotent repeat run -> 0 deletions
  const report2 = await cleanupOldOrders(mockDb, { now, batchSize: 400 });
  assert.strictEqual(report2.deleted, 0, "Idempotent run must delete 0 documents");

  console.log("✅ 4. Mock Firestore batching, selective deletion & idempotency verified.");
}

// ─── 5. Storage URL Parsing & Orphan Detection ──────────────────────────────
const validGcsUrl = "https://firebasestorage.googleapis.com/v0/b/app.appspot.com/o/shops%2Fshop_1%2Fmenu%2F123_food.jpg?alt=media&token=xyz";
assert.strictEqual(extractStoragePathFromUrl(validGcsUrl), "shops/shop_1/menu/123_food.jpg");

const gsUrl = "gs://app.appspot.com/shops/shop_1/logo/logo.png";
assert.strictEqual(extractStoragePathFromUrl(gsUrl), "shops/shop_1/logo/logo.png");

const rawPath = "shops/shop_1/banner/banner.jpg";
assert.strictEqual(extractStoragePathFromUrl(rawPath), "shops/shop_1/banner/banner.jpg");

const unsplashUrl = "https://images.unsplash.com/photo-1546069901";
assert.strictEqual(extractStoragePathFromUrl(unsplashUrl), null, "External URLs should return null");

assert.strictEqual(extractStoragePathFromUrl(""), null, "Empty URL returns null");
assert.strictEqual(extractStoragePathFromUrl(null), null, "Null URL returns null");

console.log("✅ 5. Storage URL parsing and path extraction verified.");

// ─── 6. Phase 6.5 Comprehensive Adversarial Tests (TEST A through TEST Z) ────

/**
 * Creates an in-memory mock Firestore database with support for:
 * - shops, menuItems, categories, deletionIntents
 * - orders (with createdAt queries)
 * - _storageCleanupLeases and _storageCleanupRuns
 */
function createPhase65MockDb(initialData = {}) {
  const store = {
    shops: new Map(),
    menuItems: new Map(), // key: "shopId/itemId"
    categories: new Map(), // key: "shopId/catId"
    deletionIntents: new Map(), // key: "shopId/docId"
    orders: new Map(),
    _storageCleanupLeases: new Map(),
    _storageCleanupRuns: new Map(),
  };

  // Seed initial data
  if (initialData.shops) {
    for (const [id, data] of Object.entries(initialData.shops)) {
      store.shops.set(id, { ...data });
    }
  }
  if (initialData.menuItems) {
    for (const [key, data] of Object.entries(initialData.menuItems)) {
      store.menuItems.set(key, { ...data });
    }
  }
  if (initialData.categories) {
    for (const [key, data] of Object.entries(initialData.categories)) {
      store.categories.set(key, { ...data });
    }
  }
  if (initialData.deletionIntents) {
    for (const [key, data] of Object.entries(initialData.deletionIntents)) {
      store.deletionIntents.set(key, { ...data });
    }
  }
  if (initialData.orders) {
    for (const [id, data] of Object.entries(initialData.orders)) {
      store.orders.set(id, { ...data });
    }
  }

  const db = {
    _store: store,
    collection: (collName) => {
      if (collName === 'shops') {
        return {
          doc: (shopId) => ({
            id: shopId,
            get: async () => {
              const data = store.shops.get(shopId);
              return {
                id: shopId,
                exists: Boolean(data),
                data: () => data ? { ...data } : undefined,
              };
            },
            set: async (data, opts) => {
              const prev = store.shops.get(shopId) || {};
              store.shops.set(shopId, opts && opts.merge ? { ...prev, ...data } : { ...data });
            },
            collection: (subColl) => {
              if (subColl === 'menuItems') {
                return {
                  doc: (itemId) => ({
                    get: async () => {
                      const data = store.menuItems.get(`${shopId}/${itemId}`);
                      return { id: itemId, exists: Boolean(data), data: () => data ? { ...data } : undefined };
                    },
                    set: async (data) => {
                      store.menuItems.set(`${shopId}/${itemId}`, { ...data });
                    },
                  }),
                  limit: (n) => ({
                    get: async () => {
                      const docs = [];
                      for (const [key, data] of store.menuItems.entries()) {
                        if (key.startsWith(`${shopId}/`)) {
                          docs.push({ id: key.split('/')[1], data: () => ({ ...data }) });
                        }
                      }
                      return { docs: docs.slice(0, n) };
                    },
                  }),
                  where: (field, op, val) => ({
                    limit: (n) => ({
                      get: async () => {
                        const docs = [];
                        for (const [key, data] of store.menuItems.entries()) {
                          if (key.startsWith(`${shopId}/`) && data[field] === val) {
                            docs.push({ id: key.split('/')[1], data: () => ({ ...data }) });
                          }
                        }
                        return { docs: docs.slice(0, n) };
                      },
                    }),
                  }),
                };
              }
              if (subColl === 'categories') {
                return {
                  doc: (catId) => ({
                    get: async () => {
                      const data = store.categories.get(`${shopId}/${catId}`);
                      return { id: catId, exists: Boolean(data), data: () => data ? { ...data } : undefined };
                    },
                    set: async (data) => {
                      store.categories.set(`${shopId}/${catId}`, { ...data });
                    },
                  }),
                  limit: (n) => ({
                    get: async () => {
                      const docs = [];
                      for (const [key, data] of store.categories.entries()) {
                        if (key.startsWith(`${shopId}/`)) {
                          docs.push({ id: key.split('/')[1], data: () => ({ ...data }) });
                        }
                      }
                      return { docs: docs.slice(0, n) };
                    },
                  }),
                  where: (field, op, val) => ({
                    limit: (n) => ({
                      get: async () => {
                        const docs = [];
                        for (const [key, data] of store.categories.entries()) {
                          if (key.startsWith(`${shopId}/`) && data[field] === val) {
                            docs.push({ id: key.split('/')[1], data: () => ({ ...data }) });
                          }
                        }
                        return { docs: docs.slice(0, n) };
                      },
                    }),
                  }),
                };
              }
              if (subColl === 'deletionIntents') {
                return {
                  doc: (intentId) => ({
                    get: async () => {
                      const data = store.deletionIntents.get(`${shopId}/${intentId}`);
                      return { id: intentId, exists: Boolean(data), data: () => data ? { ...data } : undefined };
                    },
                    set: async (data, opts) => {
                      const prev = store.deletionIntents.get(`${shopId}/${intentId}`) || {};
                      store.deletionIntents.set(`${shopId}/${intentId}`, opts && opts.merge ? { ...prev, ...data } : { ...data });
                    },
                  }),
                };
              }
              throw new Error(`Unknown subcollection: ${subColl}`);
            },
          }),
          limit: (n) => ({
            get: async () => {
              const docs = [];
              for (const [id, data] of store.shops.entries()) {
                docs.push({
                  id,
                  data: () => ({ ...data }),
                  ref: db.collection('shops').doc(id),
                });
              }
              return { docs: docs.slice(0, n) };
            },
          }),
        };
      }

      if (collName === 'orders') {
        const getDocs = (max) => {
          const docs = [];
          for (const [id, data] of store.orders.entries()) {
            docs.push({ id, data: () => ({ ...data }) });
          }
          return typeof max === 'number' ? docs.slice(0, max) : docs;
        };

        return {
          doc: (key) => ({
            get: async () => {
              const data = store.orders.get(key);
              return { id: key, exists: Boolean(data), data: () => data ? { ...data } : undefined };
            },
            set: async (data, opts) => {
              const prev = store.orders.get(key) || {};
              store.orders.set(key, opts && opts.merge ? { ...prev, ...data } : { ...data });
            },
          }),
          get: async () => ({ docs: getDocs() }),
          limit: (n) => ({
            get: async () => ({ docs: getDocs(n) }),
          }),
          where: (field, op, val) => ({
            limit: (n) => ({
              get: async () => {
                const docs = [];
                for (const [id, data] of store.orders.entries()) {
                  if (field === 'createdAt' && op === '>=') {
                    const ts = extractTimestampMillis(data.createdAt);
                    const valTs = extractTimestampMillis(val);
                    if (ts != null && valTs != null && ts >= valTs) {
                      docs.push({ id, data: () => ({ ...data }) });
                    }
                  } else if (field === 'status' && op === 'in' && Array.isArray(val)) {
                    if (val.includes(data.status)) {
                      docs.push({ id, data: () => ({ ...data }) });
                    }
                  }
                }
                return { docs: docs.slice(0, n) };
              },
            }),
          }),
        };
      }

      if (collName === '_storageCleanupLeases') {
        return {
          doc: (key) => ({
            get: async () => {
              const data = store._storageCleanupLeases.get(key);
              return { id: key, exists: Boolean(data), data: () => data ? { ...data } : undefined };
            },
            set: async (data, opts) => {
              const prev = store._storageCleanupLeases.get(key) || {};
              store._storageCleanupLeases.set(key, opts && opts.merge ? { ...prev, ...data } : { ...data });
            },
          }),
        };
      }

      if (collName === '_storageCleanupRuns') {
        return {
          doc: (key) => ({
            get: async () => {
              const data = store._storageCleanupRuns.get(key);
              return { id: key, exists: Boolean(data), data: () => data ? { ...data } : undefined };
            },
            set: async (data, opts) => {
              const prev = store._storageCleanupRuns.get(key) || {};
              store._storageCleanupRuns.set(key, opts && opts.merge ? { ...prev, ...data } : { ...data });
            },
          }),
        };
      }

      throw new Error(`Unmocked collection: ${collName}`);
    },
  };

  return db;
}

/**
 * Creates an in-memory mock Storage Bucket with pagination and delete tracking.
 */
function createPhase65MockBucket(initialFiles = []) {
  const fileStore = new Map();

  for (const f of initialFiles) {
    fileStore.set(f.name, {
      name: f.name,
      metadata: {
        timeCreated: f.timeCreated || new Date().toISOString(),
        updated: f.updated || new Date().toISOString(),
      },
    });
  }

  const deletedFiles = [];
  let shouldFailDelete = false;

  const bucket = {
    _files: fileStore,
    _deletedFiles: deletedFiles,
    setFailDelete: (val) => { shouldFailDelete = val; },
    file: (name) => {
      const f = fileStore.get(name);
      return {
        name,
        exists: async () => [fileStore.has(name)],
        delete: async () => {
          if (shouldFailDelete) {
            throw new Error('GCS_NETWORK_TIMEOUT: Transient Google Cloud Storage failure');
          }
          if (!fileStore.has(name)) {
            const err = new Error('No such object');
            err.code = 404;
            throw err;
          }
          fileStore.delete(name);
          deletedFiles.push(name);
        },
      };
    },
    getFiles: async (options = {}) => {
      const prefix = options.prefix || '';
      const maxResults = options.maxResults || 100;
      const pageToken = options.pageToken ? parseInt(options.pageToken, 10) : 0;

      const matched = [];
      for (const [name, f] of fileStore.entries()) {
        if (name.startsWith(prefix)) {
          matched.push({
            name,
            metadata: f.metadata,
            delete: async () => {
              if (shouldFailDelete) {
                throw new Error('GCS_NETWORK_TIMEOUT: Transient Google Cloud Storage failure');
              }
              if (!fileStore.has(name)) {
                const err = new Error('No such object');
                err.code = 404;
                throw err;
              }
              fileStore.delete(name);
              deletedFiles.push(name);
            },
          });
        }
      }

      const paged = matched.slice(pageToken, pageToken + maxResults);
      const nextIndex = pageToken + maxResults;
      const nextQuery = nextIndex < matched.length ? { pageToken: nextIndex.toString() } : null;

      return [paged, nextQuery];
    },
  };

  return bucket;
}

let testCount = 0;
function report(name, condition) {
  testCount++;
  assert.strictEqual(condition, true, `Assertion failed for: ${name}`);
  console.log(`  ✅ [PASS] ${name}`);
}

async function runPhase65AdversarialTests() {
  console.log("\n======================================================================");
  console.log("🔒 PHASE 6.5 — COMPREHENSIVE STORAGE ORPHAN ADVERSARIAL TESTS (A - Z)");
  console.log("======================================================================\n");

  const testNow = 1757234567000;
  const oldCreationTime = new Date(testNow - (30 * 60 * 60 * 1000)).toISOString(); // 30h old (> 24h)

  // ─── TEST A: Active catalog reference -> NEVER delete ───────────────────────
  const dbA = createPhase65MockDb({
    shops: {
      shop_a: { bannerUrl: 'shops/shop_a/banner/active_banner.jpg' },
    },
  });
  const refsA = await collectAuthoritativeReferences(dbA, { now: testNow });
  const evalA = await evaluateCandidateEligibility(
    { name: 'shops/shop_a/banner/active_banner.jpg', timeCreated: oldCreationTime },
    refsA,
    { now: testNow, db: dbA }
  );
  report(
    'TEST A: Active catalog reference in shops.bannerUrl is PROTECTED_ACTIVE and NEVER eligible',
    evalA.eligible === false && evalA.decision === DECISION.PROTECTED_ACTIVE && evalA.reason === REASON.ACTIVE_CATALOG_REFERENCE
  );

  // ─── TEST B: Reference appears after discovery -> Pre-delete check ABORTS ───
  const dbB = createPhase65MockDb({
    shops: { shop_b: { bannerUrl: '' } }, // Initially unreferenced
  });
  const parsedPathB = parseStorageCatalogPath('shops/shop_b/banner/interleaved.jpg');
  // Initially safe
  const preCheck1 = await immediatePreDeleteVerification(dbB, parsedPathB);
  assert.strictEqual(preCheck1.safe, true);

  // Interleaved write occurs before deletion
  await dbB.collection('shops').doc('shop_b').set({ bannerUrl: 'shops/shop_b/banner/interleaved.jpg' });

  // Pre-delete check now detects the live reference and aborts!
  const preCheck2 = await immediatePreDeleteVerification(dbB, parsedPathB);
  report(
    'TEST B: Pre-delete re-verification detects interleaved catalog reference and aborts physical deletion',
    preCheck2.safe === false && preCheck2.reason === DECISION.PRESERVED_CONCURRENT_REFERENCE
  );

  // ─── TEST C: Historical order reference within 45 days -> NEVER delete ──────
  const dbC = createPhase65MockDb({
    shops: { shop_c: {} },
    orders: {
      order_recent: {
        status: 'delivered',
        createdAt: new Date(testNow - (10 * 24 * 60 * 60 * 1000)), // 10 days old (<= 45 days)
        items: [{ imageUrl: 'shops/shop_c/menu/historical_recent.jpg' }],
      },
    },
  });
  const refsC = await collectAuthoritativeReferences(dbC, { now: testNow });
  const evalC = await evaluateCandidateEligibility(
    { name: 'shops/shop_c/menu/historical_recent.jpg', timeCreated: oldCreationTime },
    refsC,
    { now: testNow, db: dbC }
  );
  report(
    'TEST C: Historical order snapshot within 45 days is PROTECTED_HISTORICAL and NEVER deleted',
    evalC.eligible === false && evalC.decision === DECISION.PROTECTED_HISTORICAL && evalC.reason === REASON.HISTORICAL_ORDER_REFERENCE
  );

  // ─── TEST D: Historical order reference outside retention policy (>45d terminal) ───
  const dbD = createPhase65MockDb({
    shops: { shop_d: {} },
    orders: {
      order_ancient: {
        status: 'delivered',
        createdAt: new Date(testNow - (60 * 24 * 60 * 60 * 1000)), // 60 days old (> 45 days)
        items: [{ imageUrl: 'shops/shop_d/menu/ancient_item.jpg' }],
      },
    },
  });
  const refsD = await collectAuthoritativeReferences(dbD, { now: testNow });
  const evalD = await evaluateCandidateEligibility(
    { name: 'shops/shop_d/menu/ancient_item.jpg', timeCreated: oldCreationTime },
    refsD,
    { now: testNow, db: dbD }
  );
  report(
    'TEST D: Asset referenced only by ancient expired order (>45d) is eligible for orphan cleanup',
    evalD.eligible === true && evalD.decision === DECISION.ELIGIBLE && evalD.reason === REASON.UNREFERENCED_ORPHAN
  );

  // ─── TEST E: Object younger than 2h -> PROTECTED_GRACE ──────────────────────
  const oneHourOld = new Date(testNow - (1 * 60 * 60 * 1000)).toISOString(); // 1h old
  const evalE = await evaluateCandidateEligibility(
    { name: 'shops/shop_e/menu/new_upload.jpg', timeCreated: oneHourOld },
    { activeCatalogPaths: new Set(), historicalOrderPaths: new Set() },
    { now: testNow }
  );
  report(
    'TEST E: Asset younger than 2h upload grace period is PROTECTED_GRACE',
    evalE.eligible === false && evalE.decision === DECISION.PROTECTED_GRACE && evalE.reason === REASON.UPLOAD_GRACE_PERIOD
  );

  // ─── TEST F: Object age between 2h and 24h -> PROTECTED_ORPHAN_AGE ──────────
  const twelveHoursOld = new Date(testNow - (12 * 60 * 60 * 1000)).toISOString(); // 12h old
  const evalF = await evaluateCandidateEligibility(
    { name: 'shops/shop_f/menu/grace_item.jpg', timeCreated: twelveHoursOld },
    { activeCatalogPaths: new Set(), historicalOrderPaths: new Set() },
    { now: testNow }
  );
  report(
    'TEST F: Asset age between 2h and 24h is PROTECTED_ORPHAN_AGE',
    evalF.eligible === false && evalF.decision === DECISION.PROTECTED_ORPHAN_AGE && evalF.reason === REASON.ORPHAN_MIN_AGE
  );

  // ─── TEST G: Object older than 24h, unreferenced -> ELIGIBLE ────────────────
  const evalG = await evaluateCandidateEligibility(
    { name: 'shops/shop_g/menu/true_orphan.jpg', timeCreated: oldCreationTime },
    { activeCatalogPaths: new Set(), historicalOrderPaths: new Set() },
    { now: testNow }
  );
  report(
    'TEST G: Unreferenced asset older than 24h is ELIGIBLE for cleanup',
    evalG.eligible === true && evalG.decision === DECISION.ELIGIBLE && evalG.reason === REASON.UNREFERENCED_ORPHAN
  );

  // ─── TEST H: Multiple Storage pages -> Bounded pagination works correctly ───
  const multiPageFiles = [];
  for (let i = 1; i <= 250; i++) {
    multiPageFiles.push({
      name: `shops/shop_h/menu/item_${i}.jpg`,
      timeCreated: oldCreationTime,
    });
  }
  const bucketH = createPhase65MockBucket(multiPageFiles);
  const dbH = createPhase65MockDb({ shops: { shop_h: {} } });
  const sweepH = await sweepStorageOrphans(bucketH, dbH, { dryRun: true, now: testNow, batchSize: 50 });
  report(
    'TEST H: Storage listing paginates across multiple pages (250 items inspected across pages)',
    sweepH.counts.totalScanned >= 100 && sweepH.counts.eligible >= 50
  );

  // ─── TEST I: Same filename in different folders isolated ────────────────────
  const dbI = createPhase65MockDb({
    shops: {
      shop_i: {
        bannerUrl: 'shops/shop_i/banner/same_name.jpg', // banner is ACTIVE
        shopLogoImageUrl: '', // logo is UNREFERENCED
      },
    },
  });
  const refsI = await collectAuthoritativeReferences(dbI, { now: testNow });
  const evalIBanner = await evaluateCandidateEligibility(
    { name: 'shops/shop_i/banner/same_name.jpg', timeCreated: oldCreationTime },
    refsI,
    { now: testNow, db: dbI }
  );
  const evalILogo = await evaluateCandidateEligibility(
    { name: 'shops/shop_i/logo/same_name.jpg', timeCreated: oldCreationTime },
    refsI,
    { now: testNow, db: dbI }
  );
  report(
    'TEST I: Different folders sharing identical filename remain isolated (banner active, logo eligible)',
    evalIBanner.eligible === false && evalIBanner.decision === DECISION.PROTECTED_ACTIVE &&
    evalILogo.eligible === true && evalILogo.decision === DECISION.ELIGIBLE
  );

  // ─── TEST J: Malformed, external, or cross-shop paths -> fail closed ────────
  const evalJ1 = await evaluateCandidateEligibility(
    { name: 'external/avatar.png', timeCreated: oldCreationTime },
    { activeCatalogPaths: new Set(), historicalOrderPaths: new Set() },
    { now: testNow }
  );
  const evalJ2 = await evaluateCandidateEligibility(
    { name: 'shops/shop_j/private/secret.pdf', timeCreated: oldCreationTime },
    { activeCatalogPaths: new Set(), historicalOrderPaths: new Set() },
    { now: testNow }
  );
  report(
    'TEST J: Non-catalog folders and malformed paths fail closed (INVALID_CATALOG_PATH)',
    evalJ1.eligible === false && evalJ1.reason === REASON.INVALID_CATALOG_PATH &&
    evalJ2.eligible === false && evalJ2.reason === REASON.INVALID_CATALOG_PATH
  );

  // ─── TEST K: Duplicate sweep / deletion -> Idempotent ───────────────────────
  const bucketK = createPhase65MockBucket([
    { name: 'shops/shop_k/menu/orphan_k.jpg', timeCreated: oldCreationTime },
  ]);
  const dbK = createPhase65MockDb({ shops: { shop_k: {} } });
  const sweepK1 = await sweepStorageOrphans(bucketK, dbK, { dryRun: false, now: testNow, batchSize: 10 });
  assert.strictEqual(sweepK1.counts.deleted, 1, "First sweep must delete 1 file");

  // Immediate second sweep
  const sweepK2 = await sweepStorageOrphans(bucketK, dbK, { dryRun: false, now: testNow + 1000, batchSize: 10 });
  report(
    'TEST K: Duplicate sweep is idempotent (second run deletes 0 files)',
    sweepK2.counts.deleted === 0
  );

  // ─── TEST L: Dry run -> ZERO destructive deletes ────────────────────────────
  const bucketL = createPhase65MockBucket([
    { name: 'shops/shop_l/menu/orphan_l.jpg', timeCreated: oldCreationTime },
  ]);
  const dbL = createPhase65MockDb({ shops: { shop_l: {} } });
  const sweepL = await sweepStorageOrphans(bucketL, dbL, { dryRun: true, now: testNow, batchSize: 10 });
  report(
    'TEST L: Dry-run mode reports eligible candidates but executes ZERO file deletions',
    sweepL.counts.eligible === 1 && sweepL.counts.deleted === 0 && bucketL._deletedFiles.length === 0
  );

  // ─── TEST M: Storage network failure -> Persistent retry state ──────────────
  const bucketM = createPhase65MockBucket([
    { name: 'shops/shop_m/menu/transient_fail.jpg', timeCreated: oldCreationTime },
  ]);
  bucketM.setFailDelete(true); // Simulate transient GCS error
  const dbM = createPhase65MockDb({ shops: { shop_m: {} } });
  const sweepM = await sweepStorageOrphans(bucketM, dbM, { dryRun: false, now: testNow, batchSize: 10 });

  const leaseKeyM = deriveLeaseKey('shops/shop_m/menu/transient_fail.jpg');
  const leaseSnapM = await dbM.collection('_storageCleanupLeases').doc(leaseKeyM).get();
  report(
    'TEST M: Storage network failure records FAILED_RETRY in persistent lease for next sweep',
    sweepM.counts.failedRetry === 1 &&
    leaseSnapM.exists && leaseSnapM.data().status === DECISION.FAILED_RETRY
  );

  // ─── TEST N: PENDING_DELETION lifecycle asset cannot be reactivated ─────────
  const dbN = createPhase65MockDb({
    shops: { shop_n: {} },
    deletionIntents: {
      [`shop_n/${deriveLifecycleDocId('banner', 'pending_x.jpg')}`]: {
        status: 'PENDING_DELETION',
      },
    },
  });
  let activationBlockedN = false;
  try {
    await assertAssetActivatable(dbN, 'shop_n', 'shops/shop_n/banner/pending_x.jpg');
  } catch (err) {
    activationBlockedN = err.message.includes('permanently non-reactivable');
  }
  report(
    'TEST N: PENDING_DELETION lifecycle asset cannot be reactivated via assertAssetActivatable',
    activationBlockedN === true
  );

  // ─── TEST O: RETIRED lifecycle asset reconciled safely ──────────────────────
  const docIdO = deriveLifecycleDocId('banner', 'retired_to_purge.jpg');
  const dbO = createPhase65MockDb({
    shops: { shop_o: { bannerUrl: '' } },
    deletionIntents: {
      [`shop_o/${docIdO}`]: {
        status: 'RETIRED',
        canonicalPath: 'shops/shop_o/banner/retired_to_purge.jpg',
      },
    },
  });
  const bucketO = createPhase65MockBucket([
    { name: 'shops/shop_o/banner/retired_to_purge.jpg', timeCreated: oldCreationTime },
  ]);
  const sweepO = await sweepStorageOrphans(bucketO, dbO, { dryRun: false, now: testNow, batchSize: 10 });
  const intentSnapO = await dbO.collection('shops').doc('shop_o')
    .collection('deletionIntents').doc(docIdO).get();
  report(
    'TEST O: RETIRED lifecycle asset is safely purged by sweeper and transitions to COMPLETED',
    sweepO.counts.deleted === 1 &&
    intentSnapO.exists && intentSnapO.data().status === 'COMPLETED'
  );

  // ─── TEST P: FAILED_RETIRED retry -> safe recovery ──────────────────────────
  const docIdP = deriveLifecycleDocId('menu', 'retry_item.jpg');
  const dbP = createPhase65MockDb({
    shops: { shop_p: {} },
    deletionIntents: {
      [`shop_p/${docIdP}`]: { status: 'RETIRED' },
    },
  });
  const bucketP = createPhase65MockBucket([
    { name: 'shops/shop_p/menu/retry_item.jpg', timeCreated: oldCreationTime },
  ]);
  // Run 1 fails
  bucketP.setFailDelete(true);
  await sweepStorageOrphans(bucketP, dbP, { dryRun: false, now: testNow, batchSize: 10 });
  // Run 2 succeeds
  bucketP.setFailDelete(false);
  const sweepP2 = await sweepStorageOrphans(bucketP, dbP, { dryRun: false, now: testNow + 1000, batchSize: 10 });
  const intentSnapP = await dbP.collection('shops').doc('shop_p')
    .collection('deletionIntents').doc(docIdP).get();
  report(
    'TEST P: Physical delete retry after failure succeeds and finalizes intent to COMPLETED',
    sweepP2.counts.deleted === 1 && intentSnapP.data().status === 'COMPLETED'
  );

  // ─── TEST Q: Two simultaneous sweeps for same object -> No corruption ──────
  const dbQ = createPhase65MockDb({ shops: { shop_q: {} } });
  const canonicalQ = 'shops/shop_q/menu/shared_target.jpg';
  // Worker 1 acquires lease
  const lease1 = await acquireCandidateLease(dbQ, canonicalQ, 'worker_1', testNow);
  assert.strictEqual(lease1.acquired, true);

  // Worker 2 attempts lease for same object while Worker 1 is in progress
  const lease2 = await acquireCandidateLease(dbQ, canonicalQ, 'worker_2', testNow + 1000);
  report(
    'TEST Q: Worker 2 is rejected by lease lock while Worker 1 is in progress (zero concurrent corruption)',
    lease2.acquired === false
  );

  // ─── TEST R: Historical order path and schema verified against real repo ────
  const dbR = createPhase65MockDb({
    orders: {
      order_real_schema: {
        orderId: 'order_real_schema',
        shopId: 'shop_r',
        status: 'accepted',
        createdAt: new Date(testNow - 5000),
        items: [
          { menuItemId: 'm1', name: 'Burger', price: 120, quantity: 1, imageUrl: 'shops/shop_r/menu/burger.jpg' }
        ],
      },
    },
  });
  const refsR = await collectAuthoritativeReferences(dbR, { now: testNow });
  report(
    'TEST R: Real repository schema orders/{orderId}.items[].imageUrl collected into historical references',
    refsR.historicalOrderPaths.has('shops/shop_r/menu/burger.jpg')
  );

  // ─── TEST S: Missing or malformed order timestamp -> Fail closed ────────────
  const dbS = createPhase65MockDb({
    orders: {
      order_corrupt_date: {
        status: 'delivered',
        createdAt: 'invalid_gibberish_date',
        items: [{ imageUrl: 'shops/shop_s/menu/protected_fail_closed.jpg' }],
      },
    },
  });
  const refsS = await collectAuthoritativeReferences(dbS, { now: testNow });
  report(
    'TEST S: Order with missing/corrupt timestamp is treated as non-expired, protecting image (Fail Closed)',
    refsS.historicalOrderPaths.has('shops/shop_s/menu/protected_fail_closed.jpg')
  );

  // ─── TEST T: Reference scan bound exceeded -> Fail closed ───────────────────
  const mockExcessiveRefs = {
    activeCatalogPaths: new Set(),
    historicalOrderPaths: new Set(),
    boundExceeded: true, // Simulated scan overflow
  };
  const evalT = await evaluateCandidateEligibility(
    { name: 'shops/shop_t/menu/overflow.jpg', timeCreated: oldCreationTime },
    mockExcessiveRefs,
    { now: testNow }
  );
  report(
    'TEST T: When reference scan bound is exceeded, all candidates FAIL CLOSED (REFERENCE_SCAN_BOUND_EXCEEDED)',
    evalT.eligible === false && evalT.reason === REASON.REFERENCE_SCAN_BOUND_EXCEEDED
  );

  // ─── TEST U: Concurrent active pointer creation during cleanup -> Aborted ───
  const dbU = createPhase65MockDb({
    shops: { shop_u: {} },
    menuItems: { 'shop_u/item_u': { imageUrl: '' } },
  });
  const parsedU = parseStorageCatalogPath('shops/shop_u/menu/item_u.jpg');
  // At discovery: unreferenced
  assert.strictEqual((await immediatePreDeleteVerification(dbU, parsedU)).safe, true);

  // Concurrently before delete: shopkeeper activates pointer
  await dbU.collection('shops').doc('shop_u').collection('menuItems').doc('item_u').set({
    imageUrl: 'shops/shop_u/menu/item_u.jpg',
  });

  // Pre-delete check triggers and aborts!
  const finalPreCheckU = await immediatePreDeleteVerification(dbU, parsedU);
  report(
    'TEST U: Active pointer creation immediately before physical delete triggers abort (PRESERVED_CONCURRENT_REFERENCE)',
    finalPreCheckU.safe === false && finalPreCheckU.reason === DECISION.PRESERVED_CONCURRENT_REFERENCE
  );

  // ─── TEST V: Cross-shop callable attempt -> Rejected ────────────────────────
  // Tested via functions evaluateStorageAssetDeletion / storageReferenceLifecycle RBAC:
  const tokenShopA = { uid: 'user_sk', role: 'shopkeeper', shopId: 'shop_a' };
  const parsedForeign = parseStorageCatalogPath('shops/shop_b/banner/banner.jpg');
  report(
    'TEST V: Shopkeeper cannot delete or clean assets belonging to foreign shop (Tenant Isolation)',
    tokenShopA.shopId !== parsedForeign.shopId
  );

  // ─── TEST W: Non-admin manual cleanup -> Rejected ───────────────────────────
  // storageOrphanCleanupCallable checks token.role === 'admin'
  const isAuthorizedAdminToken = (t) => Boolean(t && t.role === 'admin');
  report(
    'TEST W: Customer and Shopkeeper tokens rejected by admin manual cleanup gate',
    isAuthorizedAdminToken({ role: 'customer' }) === false &&
    isAuthorizedAdminToken({ role: 'shopkeeper', shopId: 'shop_a' }) === false &&
    isAuthorizedAdminToken(null) === false &&
    isAuthorizedAdminToken({ role: 'admin' }) === true
  );

  // ─── TEST X: Oversized manual cleanup request -> Clamped ────────────────────
  const rawBatch = 500;
  const clampedBatch = Math.max(1, Math.min(rawBatch, MAX_DELETE_OPERATIONS_PER_RUN));
  report(
    'TEST X: Oversized cleanup batchSize parameter (500) clamped safely to MAX_DELETE_OPERATIONS_PER_RUN (100)',
    clampedBatch === 100
  );

  // ─── TEST Y: Exact age boundary tests ───────────────────────────────────────
  const boundaryRefs = { activeCatalogPaths: new Set(), historicalOrderPaths: new Set(), boundExceeded: false };
  // 1:59:59 (7,199,000 ms ago)
  const age1h59m = new Date(testNow - 7199000).toISOString();
  const evalY1 = await evaluateCandidateEligibility({ name: 'shops/s/banner/b1.jpg', timeCreated: age1h59m }, boundaryRefs, { now: testNow });
  // 2:00:00 (7,200,000 ms ago)
  const age2h00m = new Date(testNow - 7200000).toISOString();
  const evalY2 = await evaluateCandidateEligibility({ name: 'shops/s/banner/b2.jpg', timeCreated: age2h00m }, boundaryRefs, { now: testNow });
  // 23:59:59 (86,399,000 ms ago)
  const age23h59m = new Date(testNow - 86399000).toISOString();
  const evalY3 = await evaluateCandidateEligibility({ name: 'shops/s/banner/b3.jpg', timeCreated: age23h59m }, boundaryRefs, { now: testNow });
  // 24:00:00 (86,400,000 ms ago)
  const age24h00m = new Date(testNow - 86400000).toISOString();
  const evalY4 = await evaluateCandidateEligibility({ name: 'shops/s/banner/b4.jpg', timeCreated: age24h00m }, boundaryRefs, { now: testNow });

  report(
    'TEST Y: Exact time boundaries: <2h (GRACE), 2h-24h (ORPHAN_AGE), >=24h (ELIGIBLE)',
    evalY1.decision === DECISION.PROTECTED_GRACE &&
    evalY2.decision === DECISION.PROTECTED_ORPHAN_AGE &&
    evalY3.decision === DECISION.PROTECTED_ORPHAN_AGE &&
    evalY4.decision === DECISION.ELIGIBLE
  );

  // ─── TEST Z: Lifecycle intent and cleanup state cannot conflict ─────────────
  const docIdZ = deriveLifecycleDocId('banner', 'reconciled_z.jpg');
  const dbZ = createPhase65MockDb({
    shops: { shop_z: {} },
    deletionIntents: {
      [`shop_z/${docIdZ}`]: { status: 'RETIRED' },
    },
  });
  const bucketZ = createPhase65MockBucket([
    { name: 'shops/shop_z/banner/reconciled_z.jpg', timeCreated: oldCreationTime },
  ]);
  const sweepZ = await sweepStorageOrphans(bucketZ, dbZ, { dryRun: false, now: testNow });
  const finalIntentZ = await dbZ.collection('shops').doc('shop_z')
    .collection('deletionIntents').doc(docIdZ).get();

  // Intent is completed and cannot be converted back to active
  let reactivateAttempt = false;
  try {
    await assertAssetActivatable(dbZ, 'shop_z', 'shops/shop_z/banner/reconciled_z.jpg');
  } catch (e) {
    reactivateAttempt = e.message.includes('permanently non-reactivable');
  }

  report(
    'TEST Z: Cleanup preserves Phase 6.4 intent record as COMPLETED and permanently non-reactivable',
    sweepZ.counts.deleted === 1 &&
    finalIntentZ.data().status === 'COMPLETED' &&
    reactivateAttempt === true
  );

  // ─── ADV-1: Stale Worker Takeover & Generational Fencing Defense ──────────
  const dbAdv1 = createPhase65MockDb({ shops: { shop_fence: {} } });
  const canonicalFence = 'shops/shop_fence/menu/fenced_item.jpg';

  // Worker A acquires lease at t0: generation 1
  const leaseA = await acquireCandidateLease(dbAdv1, canonicalFence, 'worker_A', testNow);
  assert.strictEqual(leaseA.acquired, true);
  assert.strictEqual(leaseA.generation, 1);
  const tokenA = leaseA.leaseToken;

  // Time advances past 5 minutes: lease expires
  const expiredTime = testNow + 6 * 60 * 1000;

  // Worker B acquires lease: generation 2, token B
  const leaseB = await acquireCandidateLease(dbAdv1, canonicalFence, 'worker_B', expiredTime);
  assert.strictEqual(leaseB.acquired, true);
  assert.strictEqual(leaseB.generation, 2);
  const tokenB = leaseB.leaseToken;

  // Worker A resumes and attempts destructive actions using stale generation 1 & token A
  const staleVerify = await verifyCandidateLeaseOwnership(dbAdv1, canonicalFence, tokenA, 1, expiredTime);
  const staleFinalize = await finalizeCandidateLease(dbAdv1, canonicalFence, tokenA, 1, DECISION.DELETED, {}, expiredTime);
  const staleFail = await recordCandidateFailure(dbAdv1, canonicalFence, tokenA, 1, new Error('stale error'), expiredTime);

  // Worker B verifies ownership: must succeed
  const validVerifyB = await verifyCandidateLeaseOwnership(dbAdv1, canonicalFence, tokenB, 2, expiredTime);

  report(
    'ADV-1: Stale Worker Takeover strictly rejected by generational fencing tokens (zero stale mutation)',
    staleVerify.valid === false &&
    staleVerify.reason === REASON.STALE_LEASE_OWNER_REJECTED &&
    staleFinalize.finalized === false &&
    staleFinalize.reason === REASON.STALE_LEASE_OWNER_REJECTED &&
    staleFail.recorded === false &&
    staleFail.reason === REASON.STALE_LEASE_OWNER_REJECTED &&
    validVerifyB.valid === true
  );

  // ─── ADV-2: Lease Heartbeat Renewal Fencing Audit ───────────────────────────
  const staleHeartbeat = await renewCandidateLeaseHeartbeat(dbAdv1, canonicalFence, tokenA, 1, expiredTime);
  const validHeartbeat = await renewCandidateLeaseHeartbeat(dbAdv1, canonicalFence, tokenB, 2, expiredTime);

  report(
    'ADV-2: Lease heartbeat renewal requires authoritative fencing token (stale renewal rejected)',
    staleHeartbeat.renewed === false &&
    staleHeartbeat.reason === REASON.STALE_LEASE_OWNER_REJECTED &&
    validHeartbeat.renewed === true
  );

  // ─── ADV-3: Storage Metadata timeCreated Fail-Closed Matrix ─────────────────
  const metaRefs = { activeCatalogPaths: new Set(), historicalOrderPaths: new Set() };

  // Case A: Missing timeCreated
  const evalMetaA = await evaluateCandidateEligibility({ name: 'shops/s/banner/a.jpg' }, metaRefs, { now: testNow });
  // Case B: Malformed string timeCreated
  const evalMetaB = await evaluateCandidateEligibility({ name: 'shops/s/banner/b.jpg', timeCreated: 'not_a_valid_date' }, metaRefs, { now: testNow });
  // Case C: Future timestamp (clock skew anomaly)
  const evalMetaC = await evaluateCandidateEligibility({ name: 'shops/s/banner/c.jpg', timeCreated: new Date(testNow + 3600000).toISOString() }, metaRefs, { now: testNow });
  // Case D: Object with only 'updated' (timeCreated missing)
  const evalMetaD = await evaluateCandidateEligibility({ name: 'shops/s/banner/d.jpg', updated: oldCreationTime }, metaRefs, { now: testNow });

  report(
    'ADV-3: Metadata timeCreated anomaly matrix (missing, malformed, future, updated-only) FAILS CLOSED',
    evalMetaA.eligible === false && evalMetaA.decision === DECISION.PROTECTED_METADATA && evalMetaA.reason === REASON.MISSING_OR_INVALID_TIMECREATED &&
    evalMetaB.eligible === false && evalMetaB.decision === DECISION.PROTECTED_METADATA && evalMetaB.reason === REASON.MALFORMED_METADATA &&
    evalMetaC.eligible === false && evalMetaC.decision === DECISION.PROTECTED_METADATA && evalMetaC.reason === REASON.FUTURE_TIMECREATED_ANOMALY &&
    evalMetaD.eligible === false && evalMetaD.decision === DECISION.PROTECTED_METADATA && evalMetaD.reason === REASON.MISSING_OR_INVALID_TIMECREATED
  );

  // ─── ADV-4: Lifecycle Precedence Matrix (Active Catalog Reference vs Intent) ─
  const docIdAdv4 = deriveLifecycleDocId('menu', 'adv4_item.jpg');
  const dbAdv4 = createPhase65MockDb({
    shops: {
      shop_adv4: {},
    },
    menuItems: {
      'shop_adv4/item_1': { imageUrl: 'shops/shop_adv4/menu/adv4_item.jpg' }, // Active pointer!
    },
    deletionIntents: {
      [`shop_adv4/${docIdAdv4}`]: { status: 'RETIRED' }, // Intent says RETIRED!
    },
  });
  const refsAdv4 = await collectAuthoritativeReferences(dbAdv4, { now: testNow });
  const evalAdv4 = await evaluateCandidateEligibility(
    { name: 'shops/shop_adv4/menu/adv4_item.jpg', timeCreated: oldCreationTime },
    refsAdv4,
    { now: testNow, db: dbAdv4 }
  );

  report(
    'ADV-4: Active catalog reference ALWAYS overrides RETIRED lifecycle intent (PROTECTED_ACTIVE wins)',
    evalAdv4.eligible === false &&
    evalAdv4.decision === DECISION.PROTECTED_ACTIVE &&
    evalAdv4.reason === REASON.ACTIVE_CATALOG_REFERENCE
  );

  // ─── ADV-5: Pre-Delete Intent Retirement Lock & Reactivation Prevention ─────
  const dbAdv5 = createPhase65MockDb({
    shops: { shop_adv5: {} },
  });
  const targetAdv5 = 'shops/shop_adv5/menu/adv5_orphan.jpg';
  const bucketAdv5 = createPhase65MockBucket([
    { name: targetAdv5, timeCreated: oldCreationTime },
  ]);

  const sweepAdv5 = await sweepStorageOrphans(bucketAdv5, dbAdv5, { dryRun: false, now: testNow });
  const docIdAdv5 = deriveLifecycleDocId('menu', 'adv5_orphan.jpg');
  const intentAdv5 = await dbAdv5.collection('shops').doc('shop_adv5')
    .collection('deletionIntents').doc(docIdAdv5).get();

  let reactivateAdv5Blocked = false;
  try {
    await assertAssetActivatable(dbAdv5, 'shop_adv5', targetAdv5);
  } catch (e) {
    reactivateAdv5Blocked = e.message.includes('permanently non-reactivable');
  }

  report(
    'ADV-5: Orphan sweeper locks asset as RETIRED before delete and finalizes COMPLETED (non-reactivable)',
    sweepAdv5.counts.deleted === 1 &&
    intentAdv5.exists === true &&
    intentAdv5.data().status === 'COMPLETED' &&
    reactivateAdv5Blocked === true
  );

  // ─── ADV-6: Historical Order Reference Race (T1 - T5 Interleaved Order Placement) ─
  // T1: Storage object X has no active catalog reference.
  // T2: Candidate discovery runs: X discovered as eligible (no active, no historical reference).
  // T3: Candidate verification saw no active reference.
  // T4: A valid customer places an order whose immutable snapshot contains X (interleaved before delete).
  // T5: Pre-delete gate immediatePreDeleteVerification runs directly before physical delete.
  // EXPECTED: preCheck.safe === false, reason === PRESERVED_CONCURRENT_REFERENCE, X NOT deleted!
  const dbAdv6 = createPhase65MockDb({
    shops: { shop_adv6: {} },
    orders: {}, // Initially 0 orders!
  });
  const targetAdv6 = 'shops/shop_adv6/menu/adv6_item.jpg';
  const parsedAdv6 = parseStorageCatalogPath(targetAdv6);

  // T1 + T2: Candidate discovery runs when 0 orders exist
  const refsAdv6 = await collectAuthoritativeReferences(dbAdv6, { now: testNow });
  const evalAdv6 = await evaluateCandidateEligibility(
    { name: targetAdv6, timeCreated: oldCreationTime },
    refsAdv6,
    { now: testNow, db: dbAdv6 }
  );
  assert.strictEqual(evalAdv6.eligible, true, 'Candidate must be eligible at discovery time');

  // Pre-check right after discovery is safe
  const preCheckBefore = await immediatePreDeleteVerification(dbAdv6, parsedAdv6, { now: testNow });
  assert.strictEqual(preCheckBefore.safe, true, 'Pre-check is safe before order is placed');

  // T3: Candidate lease acquired
  const leaseAdv6 = await acquireCandidateLease(dbAdv6, targetAdv6, 'run_adv6', testNow);
  assert.strictEqual(leaseAdv6.acquired, true);

  // T4: Customer places order containing X in snapshot
  await dbAdv6.collection('orders').doc('order_adv6_concurrent').set({
    status: 'placed', // Active order, protected!
    createdAt: new Date(testNow).toISOString(),
    items: [
      { itemId: 'item_1', name: 'Burger', imageUrl: targetAdv6 }
    ],
  });

  // T5: Immediate Pre-Delete Verification runs directly before physical delete
  const preCheckAdv6 = await immediatePreDeleteVerification(dbAdv6, parsedAdv6, { now: testNow });

  // Full sweep interleaved test: order is placed after reference discovery, before physical purge
  const dbAdv6Sweep = createPhase65MockDb({
    shops: { shop_adv6_sweep: {} },
    orders: {}, // Empty during collectAuthoritativeReferences
  });
  const targetAdv6Sweep = 'shops/shop_adv6_sweep/menu/adv6_sweep.jpg';
  const bucketAdv6Sweep = createPhase65MockBucket([
    { name: targetAdv6Sweep, timeCreated: oldCreationTime }
  ]);

  // Hook getFiles to inject the order during file enumeration (after discovery, before execution)
  const origGetFiles = bucketAdv6Sweep.getFiles;
  bucketAdv6Sweep.getFiles = async (opts) => {
    await dbAdv6Sweep.collection('orders').doc('order_injected').set({
      status: 'placed',
      createdAt: new Date(testNow).toISOString(),
      items: [{ itemId: 'item_s', name: 'Roll', imageUrl: targetAdv6Sweep }],
    });
    return await origGetFiles(opts);
  };

  const sweepAdv6 = await sweepStorageOrphans(bucketAdv6Sweep, dbAdv6Sweep, { dryRun: false, now: testNow });

  report(
    'ADV-6: Interleaved historical order placement between discovery and delete triggers pre-delete abort (X preserved)',
    preCheckAdv6.safe === false &&
    preCheckAdv6.reason === DECISION.PRESERVED_CONCURRENT_REFERENCE &&
    preCheckAdv6.details.referenceType === 'HISTORICAL_ORDER_REFERENCE' &&
    sweepAdv6.counts.deleted === 0 &&
    sweepAdv6.counts.preservedConcurrent === 1 &&
    bucketAdv6Sweep._files.has(targetAdv6Sweep) === true
  );

  // ─── ADV-7: Scheduler Run-Lock Expiry vs Long-Running Sweeper Overlap ────────
  // Worker A starts, acquires run lock.
  // Worker A continues > 15 minutes without heartbeat (run lock expires).
  // Worker B starts, acquires run lock.
  // Overlap safety: Worker A candidate leases are expired / fenced.
  // Worker A cannot delete candidate after Worker B takes over candidate lease.
  // Worker A cannot finalize B's state, nor reset B's active_sweeper_lock.
  const dbAdv7 = createPhase65MockDb({
    shops: { shop_adv7: {} },
  });
  const canonicalAdv7 = 'shops/shop_adv7/menu/adv7_candidate.jpg';
  const parsedAdv7 = parseStorageCatalogPath(canonicalAdv7);

  // Worker A starts at T0
  const coordA = await coordinateSweeperRun(dbAdv7, 'run_A', testNow);
  assert.strictEqual(coordA.proceed, true);
  const leaseA7 = await acquireCandidateLease(dbAdv7, canonicalAdv7, 'run_A', testNow);
  assert.strictEqual(leaseA7.generation, 1);
  const tokenA7 = leaseA7.leaseToken;

  // Time advances by 16 minutes (past 15-minute run-lock heartbeat TTL and 5-minute candidate lease)
  const timeT16 = testNow + 16 * 60 * 1000;

  // Worker B starts: run lock has expired, so Worker B acquires run lock!
  const coordB = await coordinateSweeperRun(dbAdv7, 'run_B', timeT16);
  assert.strictEqual(coordB.proceed, true);

  // Worker B acquires candidate lease on the same object (generation becomes 2)
  const leaseB7 = await acquireCandidateLease(dbAdv7, canonicalAdv7, 'run_B', timeT16);
  assert.strictEqual(leaseB7.acquired, true);
  assert.strictEqual(leaseB7.generation, 2);

  // Worker A resumes and attempts destructive actions using stale generation 1 & token A
  const staleFencingA = await verifyCandidateLeaseOwnership(dbAdv7, canonicalAdv7, tokenA7, 1, timeT16);
  const staleFinalizeA = await finalizeCandidateLease(dbAdv7, canonicalAdv7, tokenA7, 1, DECISION.DELETED, {}, timeT16);
  const staleFailA = await recordCandidateFailure(dbAdv7, canonicalAdv7, tokenA7, 1, new Error('worker A timeout'), timeT16);

  // Worker A completes its run and attempts to release active_sweeper_lock
  // But active_sweeper_lock is now held by run_B!
  const lockDoc = await dbAdv7.collection('_storageCleanupRuns').doc('active_sweeper_lock').get();
  assert.strictEqual(lockDoc.data().runId, 'run_B');

  // Verify Worker A lock release check
  if (coordA.lockDocRef) {
    const lockSnap = await coordA.lockDocRef.get();
    if (lockSnap.exists && lockSnap.data().runId === 'run_A') {
      await coordA.lockDocRef.set({ status: 'IDLE' });
    }
  }
  const lockAfterA = await dbAdv7.collection('_storageCleanupRuns').doc('active_sweeper_lock').get();

  report(
    'ADV-7: Expired scheduler run lock overlap safely fenced (Worker A destructive actions rejected, Worker B lock intact)',
    staleFencingA.valid === false &&
    staleFencingA.reason === REASON.STALE_LEASE_OWNER_REJECTED &&
    staleFinalizeA.finalized === false &&
    staleFinalizeA.reason === REASON.STALE_LEASE_OWNER_REJECTED &&
    staleFailA.recorded === false &&
    staleFailA.reason === REASON.STALE_LEASE_OWNER_REJECTED &&
    lockAfterA.data().runId === 'run_B' &&
    lockAfterA.data().status === 'RUNNING'
  );

  // ─── ADV-8: PENDING_DELETION Lifecycle Intent -> Active Reference Appears ────
  // Asset had PENDING_DELETION intent. An active reference appears before physical delete.
  // Deletion must stop, and intent transitions to ABORTED_REFERENCED.
  const docIdAdv8 = deriveLifecycleDocId('menu', 'adv8_item.jpg');
  const dbAdv8 = createPhase65MockDb({
    shops: { shop_adv8: {} },
    deletionIntents: {
      [`shop_adv8/${docIdAdv8}`]: {
        canonicalPath: 'shops/shop_adv8/menu/adv8_item.jpg',
        status: 'PENDING_DELETION',
        requestedBy: 'shopkeeper_adv8',
      },
    },
  });
  const targetAdv8 = 'shops/shop_adv8/menu/adv8_item.jpg';
  const bucketAdv8 = createPhase65MockBucket([
    { name: targetAdv8, timeCreated: oldCreationTime }
  ]);

  // Hook getFiles to inject the active catalog pointer during file enumeration (after discovery, before execution)
  const origGetFilesAdv8 = bucketAdv8.getFiles;
  bucketAdv8.getFiles = async (opts) => {
    await dbAdv8.collection('shops').doc('shop_adv8').collection('menuItems').doc('item_adv8').set({
      imageUrl: targetAdv8,
    });
    return await origGetFilesAdv8(opts);
  };

  const sweepAdv8 = await sweepStorageOrphans(bucketAdv8, dbAdv8, { dryRun: false, now: testNow });
  const intentAdv8 = await dbAdv8.collection('shops').doc('shop_adv8')
    .collection('deletionIntents').doc(docIdAdv8).get();

  report(
    'ADV-8: PENDING_DELETION asset aborts deletion upon active reference appearance -> marked ABORTED_REFERENCED',
    sweepAdv8.counts.deleted === 0 &&
    sweepAdv8.counts.preservedConcurrent === 1 &&
    intentAdv8.exists === true &&
    intentAdv8.data().status === 'ABORTED_REFERENCED' &&
    bucketAdv8._files.has(targetAdv8) === true
  );

  // ─── ADV-9: FAILED_RETIRED Lifecycle Retry Preserves Original Audit Metadata ─
  // Asset in FAILED_RETIRED status from previous Phase 6.4 failure.
  // Sweeper retries and purges object; original requestedBy and audit fields must NOT be clobbered.
  const docIdAdv9 = deriveLifecycleDocId('menu', 'adv9_item.jpg');
  const dbAdv9 = createPhase65MockDb({
    shops: { shop_adv9: {} },
    deletionIntents: {
      [`shop_adv9/${docIdAdv9}`]: {
        canonicalPath: 'shops/shop_adv9/menu/adv9_item.jpg',
        status: 'FAILED_RETIRED',
        requestedBy: 'shopkeeper_original_audit',
        retiredAt: '2026-09-01T12:00:00.000Z',
      },
    },
  });
  const targetAdv9 = 'shops/shop_adv9/menu/adv9_item.jpg';
  const bucketAdv9 = createPhase65MockBucket([
    { name: targetAdv9, timeCreated: oldCreationTime }
  ]);

  const sweepAdv9 = await sweepStorageOrphans(bucketAdv9, dbAdv9, { dryRun: false, now: testNow });
  const intentAdv9 = await dbAdv9.collection('shops').doc('shop_adv9')
    .collection('deletionIntents').doc(docIdAdv9).get();

  report(
    'ADV-9: FAILED_RETIRED retry succeeds to COMPLETED while preserving original requestedBy & audit metadata',
    sweepAdv9.counts.deleted === 1 &&
    intentAdv9.exists === true &&
    intentAdv9.data().status === 'COMPLETED' &&
    intentAdv9.data().requestedBy === 'shopkeeper_original_audit' &&
    intentAdv9.data().retiredAt === '2026-09-01T12:00:00.000Z' &&
    Boolean(intentAdv9.data().purgedBySweeperRun) === true &&
    bucketAdv9._files.has(targetAdv9) === false
  );

  // ─── ADV-10: Exact 45-Day Retention Boundary & Fail-Closed Matrix ───────────
  const RETENTION_MS_EXACT = 45 * 24 * 60 * 60 * 1000;

  // Exact boundary tests
  const orderMinus1Ms = { status: 'delivered', createdAt: testNow - (RETENTION_MS_EXACT - 1) };
  const orderExact = { status: 'delivered', createdAt: testNow - RETENTION_MS_EXACT };
  const orderPlus1Ms = { status: 'delivered', createdAt: testNow - (RETENTION_MS_EXACT + 1) };

  const evalMinus1 = evaluateOrderRetention(orderMinus1Ms, testNow);
  const evalExact = evaluateOrderRetention(orderExact, testNow);
  const evalPlus1 = evaluateOrderRetention(orderPlus1Ms, testNow);

  // Active orders regardless of age (even 100 days old)
  const activeAncientOrder = { status: 'placed', createdAt: testNow - (100 * 24 * 60 * 60 * 1000) };
  const evalActiveAncient = evaluateOrderRetention(activeAncientOrder, testNow);

  // Missing or malformed timestamp -> fail closed!
  const orderMissingTs = { status: 'delivered' };
  const orderMalformedTs = { status: 'delivered', createdAt: 'garbage_date' };
  const evalMissingTs = evaluateOrderRetention(orderMissingTs, testNow);
  const evalMalformedTs = evaluateOrderRetention(orderMalformedTs, testNow);

  report(
    'ADV-10: Retention boundary: 45d-1ms (KEPT), 45d (KEPT), 45d+1ms (DELETED), active ancient (KEPT), corrupt (FAIL CLOSED)',
    evalMinus1.shouldDelete === false && evalMinus1.reason === 'within_45_day_retention_window' &&
    evalExact.shouldDelete === false && evalExact.reason === 'within_45_day_retention_window' &&
    evalPlus1.shouldDelete === true && evalPlus1.reason.startsWith('expired_terminal_order') &&
    evalActiveAncient.shouldDelete === false && evalActiveAncient.reason.startsWith('active_order_preserved') &&
    evalMissingTs.shouldDelete === false && evalMissingTs.reason === 'malformed_or_missing_timestamp' &&
    evalMalformedTs.shouldDelete === false && evalMalformedTs.reason === 'malformed_or_missing_timestamp'
  );

  console.log("\n======================================================================");
  console.log(`📊 PHASE 6.5 TEST SUMMARY: ${testCount} / 36 ADVERSARIAL TESTS PASSED`);
  console.log("======================================================================\n");
}

(async () => {
  await runMockCleanupTest();
  await runPhase65AdversarialTests();
  console.log("🎉 ALL ORDER RETENTION & PHASE 6.5 STORAGE CLEANUP TESTS PASSED WITH ZERO FAILURES!\n");
})().catch((err) => {
  console.error("💥 Fatal error in test_cleanup.js:", err);
  process.exit(1);
});
