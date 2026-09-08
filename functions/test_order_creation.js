/**
 * YummBU — Server-Authoritative Order Creation Test Suite (Phase 4.1)
 * 
 * Verifies all security invariants defined in Security Checkpoint 4.1:
 * - Customer UID derived from authenticated session
 * - Conflicting/spoofed client customerId rejected
 * - Valid active shop accepted; invalid/inactive shops rejected
 * - Menu items validated against catalog (existence, availability, shop tenancy)
 * - Client price manipulation rejected / catalog prices used
 * - Client subtotal, delivery charges, and grand total ignored
 * - Option pricing semantics preserved and loaded from catalog
 * - Multiple items and quantities calculated accurately
 * - Read efficiency: catalog reads deduplicated
 * - Initial status strictly 'placed'
 * - Server timestamps and 20-minute acceptDeadline enforced
 * - Atomic persistence in orders/{orderId}
 */

const assert = require("assert");
const {
  processServerAuthoritativeOrder,
  buildDeterministicCartKey,
} = require("./order_creation");

// ─── Lightweight Mock Firestore for Offline Verification ────────────────────
class MockFirestore {
  constructor() {
    this.data = new Map();
    this.readCounts = new Map();
  }

  _getKey(col, id) {
    return `${col}/${id}`;
  }

  setDoc(path, docData) {
    this.data.set(path, { ...docData });
  }

  collection(colName) {
    const self = this;
    return {
      doc(docId) {
        const docPath = self._getKey(colName, docId);
        return {
          async get() {
            const count = self.readCounts.get(docPath) || 0;
            self.readCounts.set(docPath, count + 1);
            const exists = self.data.has(docPath);
            return {
              exists,
              id: docId,
              data: () => (exists ? { ...self.data.get(docPath) } : undefined),
            };
          },
          async set(data) {
            self.data.set(docPath, { ...data });
          },
          async create(data) {
            if (self.data.has(docPath)) {
              const err = new Error(`Document already exists at ${docPath}`);
              err.code = 6;
              err.status = 409;
              throw err;
            }
            self.data.set(docPath, { ...data });
          },
          collection(subColName) {
            return {
              doc(subDocId) {
                const subPath = `${docPath}/${subColName}/${subDocId}`;
                return {
                  async get() {
                    const count = self.readCounts.get(subPath) || 0;
                    self.readCounts.set(subPath, count + 1);
                    const exists = self.data.has(subPath);
                    return {
                      exists,
                      id: subDocId,
                      data: () => (exists ? { ...self.data.get(subPath) } : undefined),
                    };
                  },
                  async set(data) {
                    self.data.set(subPath, { ...data });
                  },
                };
              },
            };
          },
        };
      },
    };
  }
}

// ─── Seed Helper ─────────────────────────────────────────────────────────────
function createSeededFirestore() {
  const db = new MockFirestore();

  // Seed Shop 1: Active shop with ₹30 delivery charges
  db.setDoc("shops/shop_active", {
    id: "shop_active",
    name: "Active Campus Diner",
    isActive: true,
    deliveryCharges: 30,
    deliveryNote: "Gate No. 2 Pickup",
  });

  // Seed Shop 2: Inactive / Closed shop
  db.setDoc("shops/shop_inactive", {
    id: "shop_inactive",
    name: "Closed Late Night Eatery",
    isActive: false,
    deliveryCharges: 20,
  });

  // Seed Shop 3: Shop B (for cross-tenant tests)
  db.setDoc("shops/shop_other", {
    id: "shop_other",
    name: "Other Shop",
    isActive: true,
    deliveryCharges: 15,
  });

  // Seed Menu Item 1: Standard item (Momos, ₹80)
  db.setDoc("shops/shop_active/menuItems/item_momos", {
    id: "item_momos",
    shopId: "shop_active",
    name: "Steamed Momos",
    price: 80,
    isAvailable: true,
    imageUrl: "https://example.com/momos.jpg",
  });

  // Seed Menu Item 2: Unavailable item
  db.setDoc("shops/shop_active/menuItems/item_out_of_stock", {
    id: "item_out_of_stock",
    shopId: "shop_active",
    name: "Paneer Roll",
    price: 120,
    isAvailable: false,
  });

  // Seed Menu Item 3: Item with universal option groups (fixed and choice)
  db.setDoc("shops/shop_active/menuItems/item_custom_burger", {
    id: "item_custom_burger",
    shopId: "shop_active",
    name: "Burger Deluxe",
    price: 100, // base price
    startingPrice: 130,
    isAvailable: true,
    optionGroups: [
      {
        id: "grp_size",
        name: "Choose Size",
        groupType: "fixed",
        required: true,
        options: [
          { id: "opt_regular", name: "Regular", price: 130, pricingType: "fixedPrice" },
          { id: "opt_large", name: "Large", price: 180, pricingType: "fixedPrice" },
        ],
      },
      {
        id: "grp_cheese",
        name: "Cheese Add-on",
        groupType: "choice",
        required: false,
        options: [
          { id: "opt_extra_cheese", name: "Extra Cheese", price: 25, pricingType: "priceAdjustment" },
        ],
      },
    ],
  });

  // Seed Menu Item 5: Item with only optional choice group (Filter Coffee, base ₹50)
  db.setDoc("shops/shop_active/menuItems/item_coffee", {
    id: "item_coffee",
    shopId: "shop_active",
    name: "Filter Coffee",
    price: 50,
    isAvailable: true,
    optionGroups: [
      {
        id: "grp_flavour",
        name: "Add Flavour",
        groupType: "choice",
        required: false,
        options: [
          { id: "opt_vanilla", name: "Vanilla", price: 15, pricingType: "priceAdjustment" },
        ],
      },
    ],
  });

  // Seed Menu Item 4: Belongs to shop_other (wrong shop)
  db.setDoc("shops/shop_other/menuItems/item_other_shop", {
    id: "item_other_shop",
    shopId: "shop_other",
    name: "Alien Pizza",
    price: 250,
    isAvailable: true,
  });

  // Seed Customer Profile in users collection
  db.setDoc("users/cust_verified", {
    uid: "cust_verified",
    name: "Rajat Sharma",
    phone: "9876543210",
  });

  return db;
}

// ─── Test Suite Execution ───────────────────────────────────────────────────
async function runTests() {
  console.log("==================================================");
  console.log("RUNNING BACKEND SERVER-AUTHORITATIVE ORDER TESTS (Phase 4.1)");
  console.log("==================================================");

  let passed = 0;
  function pass(desc) {
    passed++;
    console.log(`✅ [PASS] ${passed}. ${desc}`);
  }

  const fixedNow = new Date("2026-09-08T12:00:00.000Z");

  // ─── Test 1: Customer UID strictly derived from authenticated context ───────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 2 }],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    assert.strictEqual(res.order.customerId, "cust_verified");
    assert.strictEqual(res.order.customerName, "Rajat Sharma");
    assert.strictEqual(res.order.customerPhone, "9876543210");
    pass("Customer UID is derived strictly from authenticated authContext");
  }

  // ─── Test 2: Client customerId spoof attempt is rejected ────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      customerId: "victim_user_123", // Spoofed customerId!
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "permission-denied");
        assert(err.message.includes("Conflicting customerId"));
        return true;
      }
    );
    pass("Client customerId spoofing is rejected with permission-denied");
  }

  // ─── Test 3: Unauthenticated request is rejected ────────────────────────────
  {
    const db = createSeededFirestore();
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, null, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "unauthenticated");
        return true;
      }
    );
    pass("Unauthenticated order placement request is rejected");
  }

  // ─── Test 4: Valid active shop accepted & shopName/delivery derived ─────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    assert.strictEqual(res.order.shopId, "shop_active");
    assert.strictEqual(res.order.shopName, "Active Campus Diner");
    assert.strictEqual(res.order.deliveryCharges, 30);
    pass("Valid active shop is accepted and authoritative shop details are loaded");
  }

  // ─── Test 5: Nonexistent shop is rejected with not-found ────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "nonexistent_shop_999",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "not-found");
        assert(err.message.includes("does not exist"));
        return true;
      }
    );
    pass("Nonexistent shop is rejected with not-found");
  }

  // ─── Test 6: Inactive / closed shop is rejected ─────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_inactive",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "failed-precondition");
        assert(err.message.includes("currently inactive"));
        return true;
      }
    );
    pass("Inactive/closed shop is rejected with failed-precondition");
  }

  // ─── Test 7: Nonexistent menu item is rejected with not-found ───────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_ghost_missing", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "not-found");
        return true;
      }
    );
    pass("Nonexistent menu item is rejected with not-found");
  }

  // ─── Test 8: Menu item from wrong shop rejected ─────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      // Attempting to buy item_other_shop through shop_active
      items: [{ menuItemId: "item_other_shop", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        // Doc not found under shop_active/menuItems/item_other_shop
        assert.strictEqual(err.code, "not-found");
        return true;
      }
    );
    pass("Cross-shop menu item injection is rejected");
  }

  // ─── Test 9: Unavailable / out of stock item is rejected ────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_out_of_stock", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "failed-precondition");
        assert(err.message.includes("out of stock / unavailable"));
        return true;
      }
    );
    pass("Unavailable/out-of-stock menu item is rejected with failed-precondition");
  }

  // ─── Test 10: Client price manipulation ignored / catalog price used ────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_momos", // catalog price is ₹80
          quantity: 2,
          price: 1, // Attacker sends ₹1 price!
          subtotal: 2, // Attacker sends ₹2 subtotal!
        },
      ],
      subtotal: 2, // Spoofed order subtotal
      grandTotal: 2, // Spoofed grand total
      totalAmount: 2,
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    const item = res.order.items[0];

    // Verified: catalog price ₹80 used, not client's ₹1
    assert.strictEqual(item.price, 80);
    assert.strictEqual(item.subtotal, 160);
    assert.strictEqual(res.order.subtotal, 160);
    pass("Client price manipulation is ignored; catalog price is authoritatively used");
  }

  // ─── Test 11: Client deliveryCharges tampering ignored ──────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
      deliveryCharges: 0, // Attacker claims free delivery! Shop rate is ₹30
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    assert.strictEqual(res.order.deliveryCharges, 30);
    assert.strictEqual(res.order.grandTotal, 110); // 80 + 30
    assert.strictEqual(res.order.totalAmount, 110);
    pass("Client deliveryCharges tampering is ignored; authoritative shop rate applied");
  }

  // ─── Test 12: Option prices loaded authoritatively from catalog ─────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_custom_burger",
          quantity: 1,
          selectedOptions: [
            {
              groupId: "grp_size",
              optionId: "opt_large", // catalog price is ₹180 fixed
              price: 10, // Attacker attempts ₹10!
            },
            {
              groupId: "grp_cheese",
              optionId: "opt_extra_cheese", // catalog price is +₹25
              price: 0, // Attacker attempts ₹0!
            },
          ],
        },
      ],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    const item = res.order.items[0];

    // Large (180 fixed) + Extra Cheese (+25) = ₹205
    assert.strictEqual(item.price, 205);
    assert.strictEqual(item.subtotal, 205);
    assert.strictEqual(item.selectedOptions.length, 2);
    assert.strictEqual(item.selectedOptions[0].price, 180);
    assert.strictEqual(item.selectedOptions[1].price, 25);
    assert.strictEqual(item.optionsDescription, "Large · Extra Cheese");
    pass("Authoritative option pricing (fixed and choice) applied; client forged prices overridden");
  }

  // ─── Test 13: Option selection without fixed group adds base catalog price ──
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_coffee", // base price ₹50
          quantity: 1,
          selectedOptions: [
            {
              groupId: "grp_flavour",
              optionId: "opt_vanilla", // +₹15
            },
          ],
        },
      ],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    const item = res.order.items[0];
    // No fixed option selected -> base price ₹50 + vanilla ₹15 = ₹65
    assert.strictEqual(item.price, 65);
    assert.strictEqual(item.subtotal, 65);
    pass("Option selection without fixed group adds base catalog price accurately");
  }

  // ─── Test 14: Multiple items with multiple quantities calculated accurately ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        { menuItemId: "item_momos", quantity: 3 }, // 3 × 80 = 240
        {
          menuItemId: "item_custom_burger",
          quantity: 2,
          selectedOptions: [{ groupId: "grp_size", optionId: "opt_regular" }], // 2 × 130 = 260
        },
      ],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    assert.strictEqual(res.order.items.length, 2);
    assert.strictEqual(res.order.items[0].subtotal, 240);
    assert.strictEqual(res.order.items[1].subtotal, 260);
    assert.strictEqual(res.order.totalItems, 5); // 3 + 2
    assert.strictEqual(res.order.subtotal, 500); // 240 + 260
    assert.strictEqual(res.order.grandTotal, 530); // 500 + 30
    assert.strictEqual(res.order.totalAmount, 530);
    pass("Multiple items and multiple quantities calculate authoritative totals accurately");
  }

  // ─── Test 15: Read efficiency: duplicate menu items reuse loaded catalog doc ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_custom_burger",
          quantity: 1,
          selectedOptions: [{ groupId: "grp_size", optionId: "opt_regular" }],
        },
        {
          menuItemId: "item_custom_burger",
          quantity: 1,
          selectedOptions: [{ groupId: "grp_size", optionId: "opt_large" }],
        },
      ],
    };

    await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    const readKey = "shops/shop_active/menuItems/item_custom_burger";
    const readCount = db.readCounts.get(readKey) || 0;
    assert.strictEqual(readCount, 1, `Expected exactly 1 catalog read for deduplicated item, got ${readCount}`);
    pass("Read efficiency verified: duplicate items reuse single catalog document read");
  }

  // ─── Test 16: Zero quantity rejected ────────────────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 0 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("Quantity must be an integer between 1 and 99")
    );
    pass("Zero quantity item is rejected with invalid-argument");
  }

  // ─── Test 17: Negative quantity rejected ────────────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: -5 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );
    pass("Negative quantity item is rejected with invalid-argument");
  }

  // ─── Test 18: Non-integer quantity rejected ─────────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 2.5 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );
    pass("Non-integer quantity item is rejected with invalid-argument");
  }

  // ─── Test 19: Quantity > 99 rejected ────────────────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 100 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );
    pass("Quantity exceeding limit (>99) is rejected with invalid-argument");
  }

  // ─── Test 20: Empty items array rejected ────────────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );
    pass("Empty items array is rejected with invalid-argument");
  }

  // ─── Test 21: Initial status strictly 'placed' ──────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
      status: "delivered", // Attacker tries to create order pre-accepted/delivered!
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    assert.strictEqual(res.order.status, "placed");
    assert.strictEqual(res.order.rejectionReason, "");
    pass("Initial order status is strictly enforced to 'placed', ignoring client status injection");
  }

  // ─── Test 22: Server timestamps and acceptDeadline (+20 min) generated ─────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    const expectedDeadline = new Date(fixedNow.getTime() + 20 * 60 * 1000);
    assert(res.order.acceptDeadline);
    const actualDeadline = res.order.acceptDeadline.toDate ? res.order.acceptDeadline.toDate() : new Date(res.order.acceptDeadline);
    assert.strictEqual(actualDeadline.toISOString(), expectedDeadline.toISOString());
    pass("Server timestamps and 20-minute acceptDeadline are generated authoritatively");
  }

  // ─── Test 23: Order document written atomically to orders/{orderId} ─────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, {
      now: fixedNow,
      _serverOrderId: "ORD_TEST_ATOMIC_1",
    });

    const storedKey = `orders/${res.orderId}`;
    assert(db.data.has(storedKey), "Order must be persisted in MockFirestore under orders/{orderId}");
    const storedDoc = db.data.get(storedKey);
    assert.strictEqual(storedDoc.orderId, "ORD_TEST_ATOMIC_1");
    assert.strictEqual(storedDoc.subtotal, 80);
    assert.strictEqual(storedDoc.grandTotal, 110);
    pass("Order document is persisted atomically in orders/{orderId}");
  }

  // ─── Test 24: Deterministic cartKey generation matches client logic ─────────
  {
    const key1 = buildDeterministicCartKey("item_momos", []);
    assert.strictEqual(key1, "item_momos");

    const key2 = buildDeterministicCartKey("item_burger", [
      { groupId: "grp_size", optionId: "opt_large" },
      { groupId: "grp_cheese", optionId: "opt_extra" },
    ]);
    const key3 = buildDeterministicCartKey("item_burger", [
      { groupId: "grp_cheese", optionId: "opt_extra" },
      { groupId: "grp_size", optionId: "opt_large" },
    ]);
    assert.strictEqual(key2, key3, "CartKey must be identical regardless of selection array ordering");
    assert.strictEqual(key2, "item_burger|grp_cheese:opt_extra|grp_size:opt_large");
    pass("Deterministic cartKey generation matches Flutter client invariant");
  }

  // ─── Test 25: Fake option group not on menu item is rejected ────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_custom_burger",
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_size", optionId: "opt_regular" },
            { groupId: "grp_hacked_group", optionId: "opt_fake" }, // Nonexistent group!
          ],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes('Invalid option group "grp_hacked_group"')
    );
    pass("Invalid option group not present on menu item is rejected");
  }

  // ─── Test 26: Fake option ID not in group is rejected ───────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_custom_burger",
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_size", optionId: "opt_super_cheap_1_rupee" }, // Nonexistent option!
          ],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes('Invalid option "opt_super_cheap_1_rupee"')
    );
    pass("Invalid option ID not defined in catalog option group is rejected");
  }

  // ─── Test 27: Options sent for item with no option groups is rejected ───────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_momos", // Standard item without option groups
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_cheese", optionId: "opt_cheese" },
          ],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("does not accept option selections")
    );
    pass("Option selections sent for non-configurable menu item are rejected");
  }

  // ─── Test 28: Missing required option group is rejected ─────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_custom_burger", // grp_size is required
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_cheese", optionId: "opt_extra_cheese" }, // only cheese, no size!
          ],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("Missing required option selection")
    );
    pass("Order missing required option group selection is rejected");
  }

  // ─── Test 29: Client-supplied orderId is strictly rejected (Explicit Rejection)
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      orderId: "ORD_CLIENT_SUPPLIED_SPOOF",
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("Client-supplied orderId is strictly prohibited")
    );
    pass("Client-supplied orderId is strictly rejected (server-authoritative identity)");
  }

  // ─── Test 30: Server-generated orderId -> SUCCESS & autonomous uniqueness ─────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    const res1 = await processServerAuthoritativeOrder(db, authContext, request);
    const res2 = await processServerAuthoritativeOrder(db, authContext, request);

    assert(res1.orderId.startsWith("ORD_"), "Server-generated orderId must start with ORD_");
    assert(res2.orderId.startsWith("ORD_"), "Server-generated orderId must start with ORD_");
    assert.notStrictEqual(res1.orderId, res2.orderId, "Each server-generated orderId must be unique");
    pass("Server-generated orderId succeeds with cryptographically unique identifiers");
  }

  // ─── Test 31: Malformed client-supplied orderId cannot influence server identity
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      orderId: "../../orders/hacked_target",
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("Client-supplied orderId is strictly prohibited")
    );
    pass("Malformed client-supplied orderId is rejected without influencing server identity");
  }

  // ─── Test 32: Same final orderId cannot overwrite existing order ─────────────
  {
    const db = createSeededFirestore();
    // Pre-populate an existing order
    db.setDoc("orders/ORD_EXISTING_COLLISION", {
      orderId: "ORD_EXISTING_COLLISION",
      customerId: "victim_user",
      grandTotal: 500,
    });

    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, {
        now: fixedNow,
        _serverOrderId: "ORD_EXISTING_COLLISION",
      }),
      (err) => err.code === "already-exists" && err.status === 409
    );
    pass("Same final orderId cannot overwrite existing order (atomic create defense)");
  }

  // ─── Test 33: Concurrent collision cannot create two orders at the same ID ───
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request1 = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };
    const request2 = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 2 }],
    };

    const collisionId = "ORD_CONCURRENT_RACE_TARGET";

    // Simulate two concurrent requests that attempt to use the same final ID
    const results = await Promise.allSettled([
      processServerAuthoritativeOrder(db, authContext, request1, {
        now: fixedNow,
        _serverOrderId: collisionId,
      }),
      processServerAuthoritativeOrder(db, authContext, request2, {
        now: fixedNow,
        _serverOrderId: collisionId,
      }),
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");

    assert.strictEqual(fulfilled.length, 1, "Exactly one concurrent creation must succeed");
    assert.strictEqual(rejected.length, 1, "Exactly one concurrent creation must fail atomically");
    assert.strictEqual(rejected[0].reason.code, "already-exists");
    assert.strictEqual(rejected[0].reason.status, 409);

    // Verify exactly one order exists in storage at that path
    assert(db.data.has(`orders/${collisionId}`));
    pass("Concurrent collision cannot create two orders at the same ID");
  }

  console.log("==================================================");
  console.log(`ALL ${passed}/${passed} PHASE 4.1 SERVER ORDER TESTS PASSED!`);
  console.log("==================================================");
}

runTests().catch((err) => {
  console.error("❌ Test failed with error:", err);
  process.exit(1);
});
