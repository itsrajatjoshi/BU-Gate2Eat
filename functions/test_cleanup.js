/**
 * BU Gate2Eat — Node Test Suite for Server-Side Order Retention & Storage Cleanup
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
  extractStoragePathFromUrl,
} = require("./storage_cleanup");

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
  // 1. Recent delivered (10 days old) -> keep
  store.set("o_recent", { status: "delivered", createdAt: new Date(now - 10 * 24 * 60 * 60 * 1000) });
  // 2. Active placed (60 days old) -> keep
  store.set("o_active_old", { status: "placed", createdAt: new Date(now - 60 * 24 * 60 * 60 * 1000) });
  // 3. Expired delivered (50 days old) -> delete
  store.set("o_deliv_old", { status: "delivered", createdAt: new Date(now - 50 * 24 * 60 * 60 * 1000) });
  // 4. Expired cancelled (46 days old) -> delete
  store.set("o_canc_old", { status: "cancelled", createdAt: new Date(now - 46 * 24 * 60 * 60 * 1000) });
  // 5. Malformed timestamp (old query candidate) -> keep
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

(async () => {
  await runMockCleanupTest();
  console.log("\n🎉 ALL 5 TEST GROUPS PASSED WITH ZERO FAILURES!\n");
})();
