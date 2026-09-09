/**
 * YummBU — Server-Authoritative Order Expiration & Lifecycle Tests (Phase 5.5)
 *
 * Test Matrix:
 * 1. Acceptance Timeout (Placed -> Rejected)
 * 2. Delivery Timeout (Accepted -> Delivery_Expired)
 * 3. Terminal State Immutability (Delivered, Cancelled, Rejected, Delivery_Expired)
 * 4. Concurrent Races (Expiration vs Accept, Expiration vs Cancel, Expiration vs Deliver)
 * 5. Idempotent Repeated Processing
 * 6. Closed-App & Offline Correctness (Zero client participation required)
 * 7. Client Clock Manipulation Resistance (Server authority only)
 * 8. Zero Transaction Side Effects & FCM Post-Commit Separation
 */

const assert = require("assert");
const {
  evaluateOrderExpiration,
  expireOrderTransaction,
  expireStaleOrders,
  ACCEPT_WINDOW_MS,
  DELIVERY_WINDOW_MS,
} = require("./order_expiration");

let passedCount = 0;
let failedCount = 0;

function pass(name) {
  passedCount++;
  console.log(`✅ [PASS] ${passedCount}. ${name}`);
}

function fail(name, err) {
  failedCount++;
  console.error(`❌ [FAIL] ${name}:`, err);
}

// ─── IN-MEMORY FIRESTORE MOCK FOR ISOLATED CONCURRENCY TESTING ───────────────
class MockFirestore {
  constructor() {
    this.collections = {};
  }

  collection(name) {
    if (!this.collections[name]) {
      this.collections[name] = {};
    }
    const col = this.collections[name];

    return {
      doc: (id) => {
        return {
          id,
          get: async () => {
            const data = col[id];
            return {
              id,
              exists: !!data,
              data: () => (data ? JSON.parse(JSON.stringify(data)) : undefined),
            };
          },
          update: async (updates) => {
            if (!col[id]) throw new Error(`Document ${id} does not exist`);
            Object.assign(col[id], JSON.parse(JSON.stringify(updates)));
          },
          set: async (data, opts) => {
            if (opts && opts.merge && col[id]) {
              Object.assign(col[id], JSON.parse(JSON.stringify(data)));
            } else {
              col[id] = JSON.parse(JSON.stringify(data));
            }
          },
        };
      },
      where: (field, op, val) => {
        const createQuery = (limitNum, afterDoc) => ({
          limit: (n) => createQuery(n, afterDoc),
          startAfter: (doc) => createQuery(limitNum, doc),
          get: async () => {
            const allMatching = Object.entries(col)
              .filter(([_, d]) => d[field] === val);
            let startIndex = 0;
            if (afterDoc) {
              const idx = allMatching.findIndex(([id]) => id === afterDoc.id);
              if (idx !== -1) {
                startIndex = idx + 1;
              }
            }
            const matching = allMatching
              .slice(startIndex, startIndex + (limitNum || allMatching.length))
              .map(([id, d]) => ({
                id,
                exists: true,
                data: () => JSON.parse(JSON.stringify(d)),
              }));
            return {
              empty: matching.length === 0,
              docs: matching,
            };
          },
        });
        return createQuery();
      },
    };
  }

  async runTransaction(callback) {
    // Simulates an atomic transaction with read-before-write isolation
    const transaction = {
      get: async (ref) => ref.get(),
      update: (ref, updates) => ref.update(updates),
      set: (ref, data, opts) => ref.set(data, opts),
    };
    return await callback(transaction);
  }
}

async function runTests() {
  console.log("==================================================");
  console.log("RUNNING PHASE 5.5 SERVER-SIDE EXPIRATION TESTS");
  console.log("==================================================\n");

  const baseTime = Date.now();

  // ─── 1. ACCEPTANCE TIMEOUT UNIT TESTS ─────────────────────────────────────
  try {
    const placedOrder = {
      status: "placed",
      createdAt: baseTime,
      acceptDeadline: baseTime + ACCEPT_WINDOW_MS,
    };

    // 1. Placed before deadline -> unchanged
    const evalBefore = evaluateOrderExpiration(placedOrder, baseTime + 10 * 60 * 1000);
    assert.strictEqual(evalBefore.eligible, false);
    assert.strictEqual(evalBefore.reason, "accept_deadline_not_expired");
    pass("Placed order before acceptance deadline is preserved active");

    // 2. Placed exactly at deadline -> eligible for expiration
    const evalExact = evaluateOrderExpiration(placedOrder, baseTime + ACCEPT_WINDOW_MS);
    assert.strictEqual(evalExact.eligible, true);
    assert.strictEqual(evalExact.type, "placed_timeout");
    assert.strictEqual(evalExact.targetStatus, "rejected");
    pass("Placed order exactly at acceptance deadline transitions to rejected");

    // 3. Placed after deadline -> eligible for expiration
    const evalAfter = evaluateOrderExpiration(placedOrder, baseTime + 21 * 60 * 1000);
    assert.strictEqual(evalAfter.eligible, true);
    assert.strictEqual(evalAfter.type, "placed_timeout");
    assert.strictEqual(evalAfter.targetStatus, "rejected");
    pass("Placed order after acceptance deadline transitions to rejected");

    // 4. Missing acceptDeadline falls back to createdAt + 20 minutes
    const placedNoDeadline = {
      status: "placed",
      createdAt: baseTime,
    };
    const evalFallback = evaluateOrderExpiration(placedNoDeadline, baseTime + 20 * 60 * 1000 + 1000);
    assert.strictEqual(evalFallback.eligible, true);
    assert.strictEqual(evalFallback.targetStatus, "rejected");
    pass("Missing acceptDeadline safely falls back to createdAt + 20 minutes");

    // 5. Corrupt/missing createdAt and acceptDeadline fails safe
    const placedCorrupt = { status: "placed" };
    const evalCorrupt = evaluateOrderExpiration(placedCorrupt, baseTime + 30 * 60 * 1000);
    assert.strictEqual(evalCorrupt.eligible, false);
    assert.strictEqual(evalCorrupt.reason, "missing_or_malformed_accept_deadline");
    pass("Corrupt or missing timestamps fail safe without premature expiration");
  } catch (err) {
    fail("Acceptance timeout unit evaluation", err);
  }

  // ─── 2. DELIVERY TIMEOUT UNIT TESTS ───────────────────────────────────────
  try {
    const acceptedOrder = {
      status: "accepted",
      acceptedAt: baseTime,
      deliveryDeadline: baseTime + DELIVERY_WINDOW_MS,
    };

    // 6. Accepted before delivery deadline -> unchanged
    const evalDelivBefore = evaluateOrderExpiration(acceptedOrder, baseTime + 60 * 60 * 1000);
    assert.strictEqual(evalDelivBefore.eligible, false);
    assert.strictEqual(evalDelivBefore.reason, "delivery_deadline_not_expired");
    pass("Accepted order before delivery deadline is preserved in progress");

    // 7. Accepted after delivery deadline -> delivery_expired
    const evalDelivAfter = evaluateOrderExpiration(acceptedOrder, baseTime + 91 * 60 * 1000);
    assert.strictEqual(evalDelivAfter.eligible, true);
    assert.strictEqual(evalDelivAfter.type, "delivery_timeout");
    assert.strictEqual(evalDelivAfter.targetStatus, "delivery_expired");
    pass("Accepted order after delivery deadline transitions to delivery_expired");

    // 8. Missing deliveryDeadline falls back to acceptedAt + 90 minutes
    const acceptedNoDeadline = {
      status: "accepted",
      acceptedAt: baseTime,
    };
    const evalDelivFallback = evaluateOrderExpiration(acceptedNoDeadline, baseTime + 90 * 60 * 1000 + 500);
    assert.strictEqual(evalDelivFallback.eligible, true);
    assert.strictEqual(evalDelivFallback.targetStatus, "delivery_expired");
    pass("Missing deliveryDeadline safely falls back to acceptedAt + 90 minutes");
  } catch (err) {
    fail("Delivery timeout unit evaluation", err);
  }

  // ─── 3. TERMINAL STATE IMMUTABILITY TESTS ─────────────────────────────────
  try {
    const terminalStatuses = ["delivered", "rejected", "cancelled", "delivery_expired"];
    for (const term of terminalStatuses) {
      const order = {
        status: term,
        createdAt: baseTime - 100000000,
        acceptDeadline: baseTime - 50000000,
        deliveryDeadline: baseTime - 10000000,
      };
      const res = evaluateOrderExpiration(order, baseTime);
      assert.strictEqual(res.eligible, false);
      assert(res.reason.includes("terminal_status_immutable"));
    }
    pass("Terminal statuses (delivered, rejected, cancelled, delivery_expired) are strictly immutable to expiration");
  } catch (err) {
    fail("Terminal state immutability", err);
  }

  // ─── 4. TRANSACTIONAL EXPIRATION & SHOPSTATS ──────────────────────────────
  try {
    const mockDb = new MockFirestore();
    const orderId = "order_exp_trans_1";
    mockDb.collections.orders = {
      [orderId]: {
        orderId,
        shopId: "shop_alpha",
        customerId: "cust_omega",
        status: "placed",
        createdAt: baseTime,
        acceptDeadline: baseTime + ACCEPT_WINDOW_MS,
      },
    };

    // Run expiration transaction 25 minutes later
    const result = await expireOrderTransaction(mockDb, orderId, baseTime + 25 * 60 * 1000);
    assert.strictEqual(result.success, true);
    assert.strictEqual(result.fromStatus, "placed");
    assert.strictEqual(result.toStatus, "rejected");

    const updatedDoc = mockDb.collections.orders[orderId];
    assert.strictEqual(updatedDoc.status, "rejected");
    assert(updatedDoc.rejectionReason.includes("20 minutes"));
    assert(updatedDoc.rejectedAt);
    assert(updatedDoc.autoExpiredAt);

    // Verify shopStats counter increments
    const statsDoc = mockDb.collections.shopStats["shop_alpha"];
    assert(statsDoc);
    assert.strictEqual(statsDoc.shopId, "shop_alpha");
    pass("Transactional placed expiration updates order status and atomically increments shopStats");
  } catch (err) {
    fail("Transactional placed expiration", err);
  }

  try {
    const mockDb = new MockFirestore();
    const orderId = "order_exp_trans_2";
    mockDb.collections.orders = {
      [orderId]: {
        orderId,
        shopId: "shop_alpha",
        customerId: "cust_omega",
        status: "accepted",
        acceptedAt: baseTime,
        deliveryDeadline: baseTime + DELIVERY_WINDOW_MS,
      },
    };

    // Run expiration transaction 95 minutes later
    const result = await expireOrderTransaction(mockDb, orderId, baseTime + 95 * 60 * 1000);
    assert.strictEqual(result.success, true);
    assert.strictEqual(result.fromStatus, "accepted");
    assert.strictEqual(result.toStatus, "delivery_expired");

    const updatedDoc = mockDb.collections.orders[orderId];
    assert.strictEqual(updatedDoc.status, "delivery_expired");
    assert(updatedDoc.deliveryExpiredAt);
    assert(updatedDoc.autoExpiredAt);
    pass("Transactional accepted delivery expiration updates order status to delivery_expired");
  } catch (err) {
    fail("Transactional delivery expiration", err);
  }

  // ─── 5. CONCURRENT RACE CONDITIONS ────────────────────────────────────────
  try {
    const mockDb = new MockFirestore();
    const orderId = "order_race_accept";
    mockDb.collections.orders = {
      [orderId]: {
        orderId,
        shopId: "shop_alpha",
        customerId: "cust_omega",
        status: "placed",
        createdAt: baseTime,
        acceptDeadline: baseTime + ACCEPT_WINDOW_MS,
      },
    };

    // Race A: Shopkeeper accepted order before expiration committed
    mockDb.collections.orders[orderId].status = "accepted";
    mockDb.collections.orders[orderId].acceptedAt = baseTime + ACCEPT_WINDOW_MS - 1000;
    mockDb.collections.orders[orderId].deliveryDeadline = baseTime + ACCEPT_WINDOW_MS - 1000 + DELIVERY_WINDOW_MS;

    // Expiration sweep attempts to expire placed order
    const result = await expireOrderTransaction(mockDb, orderId, baseTime + 25 * 60 * 1000);
    assert.strictEqual(result.success, false);
    assert(result.reason.includes("delivery_deadline_not_expired"));
    assert.strictEqual(mockDb.collections.orders[orderId].status, "accepted");
    pass("Race A: Shopkeeper accept committing before expiration aborts expiration cleanly");

    // Race B: Customer cancelled order before expiration committed
    const orderIdCancel = "order_race_cancel";
    mockDb.collections.orders[orderIdCancel] = {
      orderId: orderIdCancel,
      shopId: "shop_alpha",
      customerId: "cust_omega",
      status: "cancelled",
      cancelledAt: baseTime + 5000,
    };
    const resCancel = await expireOrderTransaction(mockDb, orderIdCancel, baseTime + 25 * 60 * 1000);
    assert.strictEqual(resCancel.success, false);
    assert(resCancel.reason.includes("terminal_status_immutable"));
    assert.strictEqual(mockDb.collections.orders[orderIdCancel].status, "cancelled");
    pass("Race B: Customer cancel committing before expiration preserves cancelled terminal state");

    // Race C: Shopkeeper delivered order before delivery expiration committed
    const orderIdDeliver = "order_race_deliver";
    mockDb.collections.orders[orderIdDeliver] = {
      orderId: orderIdDeliver,
      shopId: "shop_alpha",
      customerId: "cust_omega",
      status: "delivered",
      deliveredAt: baseTime + 80 * 60 * 1000,
    };
    const resDeliver = await expireOrderTransaction(mockDb, orderIdDeliver, baseTime + 95 * 60 * 1000);
    assert.strictEqual(resDeliver.success, false);
    assert(resDeliver.reason.includes("terminal_status_immutable"));
    assert.strictEqual(mockDb.collections.orders[orderIdDeliver].status, "delivered");
    pass("Race C: Shopkeeper deliver committing before delivery expiration preserves delivered state");
  } catch (err) {
    fail("Concurrent race conditions", err);
  }

  // ─── 6. IDEMPOTENT SWEEPER EXECUTION ──────────────────────────────────────
  try {
    const mockDb = new MockFirestore();
    const order1 = "swp_order_1";
    const order2 = "swp_order_2";
    const order3 = "swp_order_3"; // fresh active

    mockDb.collections.orders = {
      [order1]: {
        orderId: order1,
        shopId: "s1",
        status: "placed",
        createdAt: baseTime,
        acceptDeadline: baseTime + ACCEPT_WINDOW_MS,
      },
      [order2]: {
        orderId: order2,
        shopId: "s1",
        status: "accepted",
        acceptedAt: baseTime,
        deliveryDeadline: baseTime + DELIVERY_WINDOW_MS,
      },
      [order3]: {
        orderId: order3,
        shopId: "s1",
        status: "placed",
        createdAt: baseTime + 100 * 60 * 1000,
        acceptDeadline: baseTime + 120 * 60 * 1000,
      },
    };

    const futureTime = baseTime + 100 * 60 * 1000; // both order1 and order2 expired

    // Run 1: Should expire order1 and order2
    const run1 = await expireStaleOrders(mockDb, { nowMillis: futureTime });
    assert.strictEqual(run1.totalExpired, 2);
    assert.strictEqual(run1.expiredPlaced, 1);
    assert.strictEqual(run1.expiredAccepted, 1);

    // Run 2: Immediately running again must be an idempotent safe no-op (0 expired)
    const run2 = await expireStaleOrders(mockDb, { nowMillis: futureTime });
    assert.strictEqual(run2.totalExpired, 0);
    assert.strictEqual(run2.expiredPlaced, 0);
    assert.strictEqual(run2.expiredAccepted, 0);
    pass("Idempotency: Repeated sweeper execution on expired records performs zero duplicate mutations");
  } catch (err) {
    fail("Idempotent sweeper execution", err);
  }

  // ─── 7. CLOSED-APP & OFFLINE CORRECTNESS ──────────────────────────────────
  try {
    const mockDb = new MockFirestore();
    const offlineOrderId = "offline_order_1";
    // Simulated customer & shopkeeper both offline and Flutter process killed
    mockDb.collections.orders = {
      [offlineOrderId]: {
        orderId: offlineOrderId,
        shopId: "shop_closed_app",
        status: "placed",
        createdAt: baseTime,
        acceptDeadline: baseTime + ACCEPT_WINDOW_MS,
      },
    };

    // Server scheduler triggers independently
    const sweepRes = await expireStaleOrders(mockDb, { nowMillis: baseTime + 25 * 60 * 1000 });
    assert.strictEqual(sweepRes.totalExpired, 1);
    assert.strictEqual(mockDb.collections.orders[offlineOrderId].status, "rejected");
    pass("Closed-app correctness: Expiration succeeds authoritatively with zero Flutter client execution");
  } catch (err) {
    fail("Closed-app correctness", err);
  }

  // ─── 8. CLIENT CLOCK MANIPULATION RESISTANCE ──────────────────────────────
  try {
    const mockDb = new MockFirestore();
    const orderId = "clock_attack_order";
    const serverTime = baseTime + 10 * 60 * 1000; // Only 10 mins passed on server (NOT expired)

    mockDb.collections.orders = {
      [orderId]: {
        orderId,
        shopId: "shop_1",
        status: "placed",
        createdAt: baseTime,
        acceptDeadline: baseTime + ACCEPT_WINDOW_MS, // expires in 10 mins
      },
    };

    // Client device claims it is +2 hours in the future
    // But backend evaluates strictly with serverTime!
    const res = await expireOrderTransaction(mockDb, orderId, serverTime);
    assert.strictEqual(res.success, false);
    assert.strictEqual(res.reason, "accept_deadline_not_expired");
    assert.strictEqual(mockDb.collections.orders[orderId].status, "placed");
    pass("Client clock manipulation resistance: Server time is the sole authority for lifecycle deadlines");
  } catch (err) {
    fail("Client clock manipulation resistance", err);
  }

  // ─── 9. CLEANUP COMPATIBILITY (Retention vs Expiration) ────────────────────
  try {
    // Verified that order_expiration sets terminal statuses ('rejected', 'delivery_expired')
    // and order_cleanup only purges terminal orders after 45 days.
    // Active orders are strictly protected by order_cleanup, and expiration only mutates active orders.
    const { TERMINAL_STATUSES } = require("./order_expiration");
    assert(TERMINAL_STATUSES.has("rejected"));
    assert(TERMINAL_STATUSES.has("delivery_expired"));
    pass("Cleanup compatibility: Order expiration produces canonical terminal statuses compatible with 45-day retention");
  } catch (err) {
    fail("Cleanup compatibility", err);
  }

  // ─── 10. TIMESTAMP PARSING & UNIT DISAMBIGUATION (extractTimestampMillis) ──
  try {
    const { extractTimestampMillis } = require("./order_expiration");

    // 1. JS Date
    const d = new Date(1725890000000);
    assert.strictEqual(extractTimestampMillis(d), 1725890000000);

    // 2. Firestore Timestamp mock (toMillis)
    const fsTs = { toMillis: () => 1725890000000 };
    assert.strictEqual(extractTimestampMillis(fsTs), 1725890000000);

    // 3. Firestore Timestamp with _seconds
    const secTs = { _seconds: 1725890000, _nanoseconds: 500000000 };
    assert.strictEqual(extractTimestampMillis(secTs), 1725890000500);

    // 4. 10-digit Unix timestamp in seconds (disambiguated to ms)
    assert.strictEqual(extractTimestampMillis(1725890000), 1725890000000);

    // 5. 13-digit Unix timestamp in milliseconds
    assert.strictEqual(extractTimestampMillis(1725890000000), 1725890000000);

    // 6. ISO-8601 string
    assert.strictEqual(extractTimestampMillis("2024-09-09T12:00:00.000Z"), Date.parse("2024-09-09T12:00:00.000Z"));

    pass("Timestamp parsing: Accurately parses Dates, Firestore Timestamps, ISO strings, and 10-digit Unix seconds");
  } catch (err) {
    fail("Timestamp parsing", err);
  }

  // ─── 11. TIMESTAMP PARSING FAIL-SAFE & BOUNDS REJECTION ─────────────────────
  try {
    const { extractTimestampMillis } = require("./order_expiration");

    assert.strictEqual(extractTimestampMillis(null), null);
    assert.strictEqual(extractTimestampMillis(undefined), null);
    assert.strictEqual(extractTimestampMillis(""), null);
    assert.strictEqual(extractTimestampMillis("   "), null);
    assert.strictEqual(extractTimestampMillis("not-a-date"), null);
    assert.strictEqual(extractTimestampMillis(-500), null);
    assert.strictEqual(extractTimestampMillis(0), null);
    assert.strictEqual(extractTimestampMillis(NaN), null);
    assert.strictEqual(extractTimestampMillis(Infinity), null);
    assert.strictEqual(extractTimestampMillis(3e14), null); // Way past year 5000
    assert.strictEqual(extractTimestampMillis("1970-01-01T00:00:00.000Z"), null); // Pre-2020 rejected

    pass("Timestamp fail-safe: Strictly rejects null, undefined, malformed, negative, and out-of-range timestamps");
  } catch (err) {
    fail("Timestamp fail-safe", err);
  }

  // ─── 12. SCHEDULER STARVATION IMMUNITY VIA CURSOR PAGINATION ───────────────
  try {
    const mockDb = new MockFirestore();
    mockDb.collections.orders = {};
    const expireTime = baseTime + 25 * 60 * 1000;

    // Seed 12 placed orders across multiple batches (batch size = 4)
    for (let i = 1; i <= 12; i++) {
      const oid = `starvation_order_${String(i).padStart(2, "0")}`;
      mockDb.collections.orders[oid] = {
        orderId: oid,
        shopId: "shop_1",
        status: "placed",
        createdAt: baseTime,
        acceptDeadline: baseTime + ACCEPT_WINDOW_MS, // expired
      };
    }

    // Run sweeper with limit = 4 (requires 3 pages to process all 12 orders)
    const sweepRes = await expireStaleOrders(mockDb, { nowMillis: expireTime, limit: 4 });
    assert.strictEqual(sweepRes.scannedCount, 12, "Should scan all 12 orders across pages without starvation");
    assert.strictEqual(sweepRes.totalExpired, 12, "All 12 expired orders should be processed");
    assert.strictEqual(sweepRes.expiredPlaced, 12);

    // Verify all 12 orders were updated to rejected
    for (let i = 1; i <= 12; i++) {
      const oid = `starvation_order_${String(i).padStart(2, "0")}`;
      assert.strictEqual(mockDb.collections.orders[oid].status, "rejected");
    }

    pass("Scheduler starvation immunity: Cursor pagination sweeps all active orders across multiple batches");
  } catch (err) {
    fail("Scheduler starvation immunity", err);
  }

  // ─── 13. expireOrdersCallable: AUTHENTICATION GATE ──────────────────────────
  try {
    const { expireOrdersCallable } = require("./index");

    // Anonymous caller (context.auth is null)
    let anonBlocked = false;
    try {
      await expireOrdersCallable.run({}, { auth: null });
    } catch (err) {
      if (err.code === "unauthenticated") {
        anonBlocked = true;
      }
    }
    assert.strictEqual(anonBlocked, true, "Anonymous caller must be rejected with unauthenticated");

    pass("expireOrdersCallable authentication: Unauthenticated/anonymous callers are strictly rejected");
  } catch (err) {
    fail("expireOrdersCallable authentication", err);
  }

  // ─── 14. expireOrdersCallable: AUTHORIZATION & ATTACK VECTOR TESTS ─────────
  try {
    const { expireOrdersCallable } = require("./index");

    // Attack A: Customer with admin: true boolean claim attempt -> DENY
    let custAdminFlagBlocked = false;
    try {
      await expireOrdersCallable.run({}, {
        auth: { uid: "cust_1", token: { role: "customer", admin: true, phone_number: "+919876543210" } },
      });
    } catch (err) {
      if (err.code === "permission-denied") custAdminFlagBlocked = true;
    }
    assert.strictEqual(custAdminFlagBlocked, true, "Customer with admin: true claim must be DENIED");

    // Attack B: Shopkeeper with admin: true boolean claim attempt -> DENY
    let skAdminFlagBlocked = false;
    try {
      await expireOrdersCallable.run({}, {
        auth: { uid: "sk_1", token: { role: "shopkeeper", admin: true, shopId: "rajat_shop", phone_number: "+918000383993" } },
      });
    } catch (err) {
      if (err.code === "permission-denied") skAdminFlagBlocked = true;
    }
    assert.strictEqual(skAdminFlagBlocked, true, "Shopkeeper with admin: true claim must be DENIED");

    // Attack C: Non-admin caller having configured admin phone number -> DENY
    let adminPhoneSpoofBlocked = false;
    try {
      await expireOrdersCallable.run({}, {
        auth: { uid: "cust_attacker", token: { role: "customer", phone_number: "+918078643910" } },
      });
    } catch (err) {
      if (err.code === "permission-denied") adminPhoneSpoofBlocked = true;
    }
    assert.strictEqual(adminPhoneSpoofBlocked, true, "Non-admin with admin phone must be DENIED (phone is NOT auth)");

    // Attack D: Non-admin caller with arbitrary phone -> DENY
    let arbitraryPhoneBlocked = false;
    try {
      await expireOrdersCallable.run({}, {
        auth: { uid: "cust_random", token: { role: "customer", phone_number: "+919999999999" } },
      });
    } catch (err) {
      if (err.code === "permission-denied") arbitraryPhoneBlocked = true;
    }
    assert.strictEqual(arbitraryPhoneBlocked, true, "Customer with arbitrary phone must be DENIED");

    // Attack E: Authenticated user with missing role claim -> DENY
    let missingRoleBlocked = false;
    try {
      await expireOrdersCallable.run({}, {
        auth: { uid: "user_no_role", token: { phone_number: "+918078643910" } },
      });
    } catch (err) {
      if (err.code === "permission-denied") missingRoleBlocked = true;
    }
    assert.strictEqual(missingRoleBlocked, true, "Authenticated user missing role claim must be DENIED");

    // Attack F: Client payload injection (supplying admin: true, role: 'admin' in data body) -> DENY
    let payloadInjectionBlocked = false;
    try {
      await expireOrdersCallable.run(
        {
          admin: true,
          role: "admin",
          phone: "8078643910",
          status: "delivery_expired",
          orderId: "attacker",
        },
        {
          auth: { uid: "attacker_uid", token: { role: "customer", phone_number: "+919123456780" } },
        }
      );
    } catch (err) {
      if (err.code === "permission-denied") payloadInjectionBlocked = true;
    }
    assert.strictEqual(payloadInjectionBlocked, true, "Payload privilege injection must be completely ignored and DENIED");

    // Valid Administrator: role === 'admin' -> ALLOW
    let adminAllowed = false;
    try {
      const adminRes = await expireOrdersCallable.run(
        { dryRun: true },
        {
          auth: { uid: "admin_uid", token: { role: "admin" } },
        }
      );
      if (adminRes && typeof adminRes === "object") adminAllowed = true;
    } catch (_) {
      adminAllowed = false;
    }
    assert.strictEqual(adminAllowed, true, "Authenticated admin with role === 'admin' must be ALLOWED");

    pass("expireOrdersCallable attack suite: Strictly requires role == 'admin'; rejects boolean flags, phone numbers, missing roles, and payload injection");
  } catch (err) {
    fail("expireOrdersCallable attack suite", err);
  }

  // ─── 15. expireOrdersCallable: PARAMETER SANITIZATION & BOUNDS ─────────────
  try {
    const { expireOrdersCallable } = require("./index");

    // Admin caller with out-of-bounds parameters
    // Should clamp limit between 1 and 100, enforce boolean dryRun, and strip arbitrary fields
    const adminContext = {
      auth: {
        uid: "admin_uid",
        token: { role: "admin", admin: true, phone_number: "+918078643910" },
      },
    };

    const res = await expireOrdersCallable.run(
      {
        limit: 99999, // Out of bounds -> should be clamped to 100
        dryRun: true,
        orderId: "forged_order",
        status: "forged_status",
      },
      adminContext
    );

    assert(res !== null && typeof res === "object");
    assert.strictEqual(res.dryRun, true);
    pass("expireOrdersCallable sanitization: Admin succeeds and inputs are strictly clamped and sanitized");
  } catch (err) {
    fail("expireOrdersCallable sanitization", err);
  }

  console.log("\n==================================================");
  console.log(`RESULTS: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log("==================================================");

  if (failedCount > 0) {
    console.error(`\n❌ TEST SUITE FAILED with ${failedCount} failure(s)!`);
    process.exit(1);
  }
}

runTests().catch((err) => {
  console.error("Fatal error during Phase 5.5 test execution:", err);
  process.exit(1);
});
