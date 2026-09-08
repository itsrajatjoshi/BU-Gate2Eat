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
  toPaise,
  fromPaise,
  MAX_ITEMS_PER_ORDER,
  MAX_ITEM_QUANTITY,
  MAX_TOTAL_QUANTITY,
  MAX_ITEM_PRICE,
  MAX_ORDER_GRAND_TOTAL,
  MAX_OPTIONS_PER_ITEM,
  MAX_CUSTOMER_NAME_LENGTH,
  MAX_CUSTOMER_PHONE_LENGTH,
  MAX_SPECIAL_INSTRUCTIONS_LENGTH,
  MAX_DELIVERY_NOTE_LENGTH,
  ID_REGEX,
  CONTROL_CHAR_REGEX,
  PROHIBITED_SECURITY_KEYS,
  ALLOWED_ORDER_METHODS,
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

  // Seed Menu Item with negative option price (Mandatory Correction 1 test)
  db.setDoc("shops/shop_active/menuItems/item_neg_opt_price", {
    id: "item_neg_opt_price",
    shopId: "shop_active",
    name: "Defective Burger",
    price: 100,
    isAvailable: true,
    optionGroups: [
      {
        id: "grp_sauce",
        name: "Sauce",
        groupType: "choice",
        required: false,
        options: [
          { id: "opt_neg_sauce", name: "Bad Sauce", price: -20, pricingType: "priceAdjustment" },
        ],
      },
    ],
  });

  // Seed Menu Item with non-finite (NaN / Infinity) option price (Mandatory Correction 1 test)
  db.setDoc("shops/shop_active/menuItems/item_nan_opt_price", {
    id: "item_nan_opt_price",
    shopId: "shop_active",
    name: "NaN Burger",
    price: 100,
    isAvailable: true,
    optionGroups: [
      {
        id: "grp_sauce",
        name: "Sauce",
        groupType: "choice",
        required: false,
        options: [
          { id: "opt_nan_sauce", name: "NaN Sauce", price: NaN, pricingType: "priceAdjustment" },
        ],
      },
    ],
  });

  // Seed Menu Item with valid 0 (free) option and selectionOnly option
  db.setDoc("shops/shop_active/menuItems/item_free_option", {
    id: "item_free_option",
    shopId: "shop_active",
    name: "Item with Free Option",
    price: 80,
    isAvailable: true,
    optionGroups: [
      {
        id: "grp_addons",
        name: "Free Addon",
        groupType: "choice",
        required: false,
        options: [
          { id: "opt_free_dip", name: "Free Mint Dip", price: 0, pricingType: "priceAdjustment" },
          { id: "opt_fork", name: "Include Fork", price: 0, pricingType: "selectionOnly" },
        ],
      },
    ],
  });

  // Seed Menu Item with negative base catalog price
  db.setDoc("shops/shop_active/menuItems/item_neg_base_price", {
    id: "item_neg_base_price",
    shopId: "shop_active",
    name: "Negative Base Price Item",
    price: -50,
    isAvailable: true,
  });

  // Seed Menu Item with non-finite base catalog price
  db.setDoc("shops/shop_active/menuItems/item_nan_base_price", {
    id: "item_nan_base_price",
    shopId: "shop_active",
    name: "NaN Base Price Item",
    price: NaN,
    isAvailable: true,
  });

  // Seed Shop with negative delivery charges
  db.setDoc("shops/shop_neg_delivery", {
    id: "shop_neg_delivery",
    name: "Negative Delivery Shop",
    isActive: true,
    deliveryCharges: -10,
  });

  // Seed Menu Item with multi-select option group (Mandatory Correction 2)
  db.setDoc("shops/shop_active/menuItems/item_multi_pizza", {
    id: "item_multi_pizza",
    shopId: "shop_active",
    name: "Custom Pizza",
    price: 200,
    isAvailable: true,
    optionGroups: [
      {
        id: "grp_toppings",
        name: "Toppings (Choose up to 3)",
        groupType: "choice",
        multiple: true,
        maxSelections: 3,
        minSelections: 1,
        options: [
          { id: "opt_olives", name: "Black Olives", price: 30, pricingType: "priceAdjustment" },
          { id: "opt_mushrooms", name: "Mushrooms", price: 35, pricingType: "priceAdjustment" },
          { id: "opt_corn", name: "Sweet Corn", price: 25, pricingType: "priceAdjustment" },
          { id: "opt_jalapenos", name: "Jalapenos", price: 30, pricingType: "priceAdjustment" },
        ],
      },
    ],
  });

  // Seed Menu Item & Shop with decimal pricing (Mandatory Correction 4 test)
  db.setDoc("shops/shop_active/menuItems/item_decimal_pasta", {
    id: "item_decimal_pasta",
    shopId: "shop_active",
    name: "Penne Alfredo",
    price: 49.50,
    isAvailable: true,
    optionGroups: [
      {
        id: "grp_extra",
        name: "Pasta Extras",
        groupType: "choice",
        required: false,
        options: [
          { id: "opt_herbs", name: "Extra Herbs", price: 12.25, pricingType: "priceAdjustment" },
        ],
      },
    ],
  });

  // Seed Shop with decimal delivery charges
  db.setDoc("shops/shop_decimal", {
    id: "shop_decimal",
    name: "Decimal Delivery Shop",
    isActive: true,
    deliveryCharges: 25.50,
  });
  db.setDoc("shops/shop_decimal/menuItems/item_decimal_pasta", {
    id: "item_decimal_pasta",
    shopId: "shop_decimal",
    name: "Penne Alfredo",
    price: 49.50,
    isAvailable: true,
    optionGroups: [
      {
        id: "grp_extra",
        name: "Pasta Extras",
        groupType: "choice",
        required: false,
        options: [
          { id: "opt_herbs", name: "Extra Herbs", price: 12.25, pricingType: "priceAdjustment" },
        ],
      },
    ],
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

  // ===========================================================================
  // PHASE 4.2 — SERVER-AUTHORITATIVE PRICING HARDENING TESTS
  // ===========================================================================

  // ─── Test 34: Negative option price in catalog is rejected (Mandatory Correction 1) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_neg_opt_price",
          quantity: 1,
          selectedOptions: [{ groupId: "grp_sauce", optionId: "opt_neg_sauce" }],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "failed-precondition");
        assert(err.message.includes("invalid or negative price"));
        return true;
      }
    );
    pass("Negative catalog option price is rejected with failed-precondition (no silent clamping to 0)");
  }

  // ─── Test 35: Non-finite option price in catalog is rejected (Mandatory Correction 1) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_nan_opt_price",
          quantity: 1,
          selectedOptions: [{ groupId: "grp_sauce", optionId: "opt_nan_sauce" }],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "failed-precondition");
        assert(err.message.includes("invalid or negative price"));
        return true;
      }
    );
    pass("Non-finite catalog option price is rejected with failed-precondition");
  }

  // ─── Test 36: Valid zero (free) option price in catalog is allowed (Mandatory Correction 1) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_free_option",
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_addons", optionId: "opt_free_dip" },
            { groupId: "grp_addons", optionId: "opt_fork" },
          ],
        },
      ],
    };

    // Note: grp_addons is a single-select choice group by default, so selecting both should be tested under multi-select
    // Let's test each free option separately:
    const res1 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_free_option",
          quantity: 1,
          selectedOptions: [{ groupId: "grp_addons", optionId: "opt_free_dip" }],
        },
      ],
    }, { now: fixedNow });
    assert.strictEqual(res1.order.items[0].price, 80); // 80 base + 0 dip
    assert.strictEqual(res1.order.items[0].selectedOptions[0].price, 0);

    const res2 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_free_option",
          quantity: 1,
          selectedOptions: [{ groupId: "grp_addons", optionId: "opt_fork" }],
        },
      ],
    }, { now: fixedNow });
    assert.strictEqual(res2.order.items[0].price, 80); // 80 base + 0 selectionOnly
    assert.strictEqual(res2.order.items[0].selectedOptions[0].price, 0);
    pass("Valid zero (free) option price and selectionOnly option are allowed with exact 0 price");
  }

  // ─── Test 37: Negative base catalog price is rejected (Mandatory Correction 1) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_neg_base_price", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "failed-precondition");
        assert(err.message.includes("invalid or negative price"));
        return true;
      }
    );
    pass("Negative catalog base price is rejected with failed-precondition");
  }

  // ─── Test 38: Non-finite base catalog price is rejected (Mandatory Correction 1) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [{ menuItemId: "item_nan_base_price", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "failed-precondition");
        assert(err.message.includes("invalid or negative price"));
        return true;
      }
    );
    pass("Non-finite catalog base price is rejected with failed-precondition");
  }

  // ─── Test 39: Negative shop delivery charges in catalog is rejected ─────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_neg_delivery",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "failed-precondition");
        assert(err.message.includes("invalid or negative delivery charges"));
        return true;
      }
    );
    pass("Negative shop delivery charges in catalog are rejected with failed-precondition");
  }

  // ─── Test 40: Multi-select group: valid multi-selection succeeds (Mandatory Correction 2) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_multi_pizza", // base 200, grp_toppings max 3, min 1
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_toppings", optionId: "opt_olives" }, // +30
            { groupId: "grp_toppings", optionId: "opt_mushrooms" }, // +35
          ],
        },
      ],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    const item = res.order.items[0];
    // Base 200 + 30 + 35 = 265
    assert.strictEqual(item.price, 265);
    assert.strictEqual(item.subtotal, 265);
    assert.strictEqual(item.selectedOptions.length, 2);
    assert.strictEqual(item.optionsDescription, "Black Olives · Mushrooms");
    pass("Multi-select option group allows valid multiple selections according to catalog schema");
  }

  // ─── Test 41: Multi-select group: exceeding maxSelections is rejected (Mandatory Correction 2) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_multi_pizza", // grp_toppings maxSelections: 3
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_toppings", optionId: "opt_olives" },
            { groupId: "grp_toppings", optionId: "opt_mushrooms" },
            { groupId: "grp_toppings", optionId: "opt_corn" },
            { groupId: "grp_toppings", optionId: "opt_jalapenos" }, // 4 selections > 3!
          ],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "invalid-argument");
        assert(err.message.includes("Too many options selected for group"));
        return true;
      }
    );
    pass("Multi-select group exceeding authoritative maxSelections is rejected");
  }

  // ─── Test 42: Single-select group: multiple distinct selections rejected (Mandatory Correction 2) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_custom_burger", // grp_size is single-select fixed (max: 1)
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_size", optionId: "opt_regular" },
            { groupId: "grp_size", optionId: "opt_large" }, // Attempting 2 sizes!
          ],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "invalid-argument");
        assert(err.message.includes("Too many options selected for group"));
        return true;
      }
    );
    pass("Single-select group with multiple distinct selections is rejected");
  }

  // ─── Test 43: Duplicate selection of exact same optionId within a group rejected ──
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_multi_pizza",
          quantity: 1,
          selectedOptions: [
            { groupId: "grp_toppings", optionId: "opt_olives" },
            { groupId: "grp_toppings", optionId: "opt_olives" }, // Duplicate identical option!
          ],
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "invalid-argument");
        assert(err.message.includes("Duplicate selection of option"));
        return true;
      }
    );
    pass("Duplicate selection of the exact same option within a group is rejected");
  }

  // ─── Test 44: Missing required selection for group with minSelections > 0 rejected ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };
    const request = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_multi_pizza", // minSelections: 1
          quantity: 1,
          selectedOptions: [], // 0 selections < minSelections (1)
        },
      ],
    };

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow }),
      (err) => {
        assert.strictEqual(err.code, "invalid-argument");
        assert(err.message.includes("Missing required option selection for group"));
        return true;
      }
    );
    pass("Missing required selection for group with minSelections > 0 is rejected");
  }

  // ─── Test 45: Quantity boundary testing (Mandatory Correction 3) ────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // 1. boundary - 1: quantity = 98 -> ALLOW
    const res98 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 98 }],
    }, { now: fixedNow });
    assert.strictEqual(res98.order.items[0].quantity, 98);

    // 2. boundary: quantity = 99 -> ALLOW
    const res99 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 99 }],
    }, { now: fixedNow });
    assert.strictEqual(res99.order.items[0].quantity, 99);

    // 3. boundary + 1: quantity = 100 -> DENY
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 100 }],
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("Quantity must be an integer between 1 and 99")
    );

    // 4. lower boundary: quantity = 1 -> ALLOW
    const res1 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    }, { now: fixedNow });
    assert.strictEqual(res1.order.items[0].quantity, 1);

    // 5. lower boundary - 1: quantity = 0 -> DENY
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 0 }],
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );
    pass("Quantity boundaries (1, 98, 99 allowed; 0, 100 denied) strictly enforced");
  }

  // ─── Test 46: Items per order boundary testing (Mandatory Correction 3) ────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // Create 50 distinct items in catalog
    const items50 = [];
    for (let i = 1; i <= 50; i++) {
      const id = `item_bulk_${i}`;
      db.setDoc(`shops/shop_active/menuItems/${id}`, {
        id,
        shopId: "shop_active",
        name: `Bulk Item ${i}`,
        price: 10,
        isAvailable: true,
      });
      items50.push({ menuItemId: id, quantity: 1 });
    }

    // 50 items (boundary) -> ALLOW
    const res50 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: items50,
    }, { now: fixedNow });
    assert.strictEqual(res50.order.items.length, 50);

    // 51 items (boundary + 1) -> DENY
    db.setDoc("shops/shop_active/menuItems/item_bulk_51", {
      id: "item_bulk_51",
      shopId: "shop_active",
      name: "Bulk Item 51",
      price: 10,
      isAvailable: true,
    });
    const items51 = [...items50, { menuItemId: "item_bulk_51", quantity: 1 }];

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: items51,
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("cannot contain more than 50 distinct items")
    );
    pass("Items per order boundaries (50 allowed, 51 denied) strictly enforced");
  }

  // ─── Test 47: Total items quantity boundary testing (Mandatory Correction 3) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // 5 items * 99 = 495, + 1 item * 5 = 500 (boundary) -> ALLOW
    const items500 = [
      { menuItemId: "item_momos", quantity: 99 },
      { menuItemId: "item_coffee", quantity: 99 },
      { menuItemId: "item_custom_burger", quantity: 99, selectedOptions: [{ groupId: "grp_size", optionId: "opt_regular" }] },
      { menuItemId: "item_multi_pizza", quantity: 99, selectedOptions: [{ groupId: "grp_toppings", optionId: "opt_olives" }] },
      { menuItemId: "item_decimal_pasta", quantity: 99 },
      { menuItemId: "item_free_option", quantity: 5 },
    ];
    const res500 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: items500,
    }, { now: fixedNow });
    assert.strictEqual(res500.order.totalItems, 500);

    // 501 total quantity (boundary + 1) -> DENY
    const items501 = [
      ...items500.slice(0, 5),
      { menuItemId: "item_free_option", quantity: 6 }, // 495 + 6 = 501
    ];
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: items501,
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("exceeds allowable limit of 500")
    );
    pass("Total order item quantity boundaries (500 allowed, 501 denied) strictly enforced");
  }

  // ─── Test 48: Item unit price ceiling testing (Mandatory Correction 3) ──────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // 1. ₹100,000 (boundary) -> ALLOW
    db.setDoc("shops/shop_active/menuItems/item_max_price", {
      id: "item_max_price",
      shopId: "shop_active",
      name: "Luxury Banquet",
      price: 100000,
      isAvailable: true,
    });
    const res100k = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [{ menuItemId: "item_max_price", quantity: 1 }],
    }, { now: fixedNow });
    assert.strictEqual(res100k.order.items[0].price, 100000);

    // 2. ₹100,001 (boundary + 1) -> DENY
    db.setDoc("shops/shop_active/menuItems/item_over_price", {
      id: "item_over_price",
      shopId: "shop_active",
      name: "Overpriced Item",
      price: 100001,
      isAvailable: true,
    });
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_over_price", quantity: 1 }],
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("exceeds allowable maximum limit of ₹100000")
    );
    pass("Item unit price ceiling boundaries (₹100,000 allowed, ₹100,001 denied) strictly enforced");
  }

  // ─── Test 49: Grand total ceiling testing (> ₹500,000 rejected) ──────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // 5 items * 99 quantity * ₹1,000 = ₹495,000 + 30 delivery = ₹495,030 (< ₹500,000) -> ALLOW
    db.setDoc("shops/shop_active/menuItems/item_1k", {
      id: "item_1k",
      shopId: "shop_active",
      name: "1K Item",
      price: 1000,
      isAvailable: true,
    });
    const resAllow = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [
        { menuItemId: "item_1k", quantity: 99 },
        { menuItemId: "item_1k", quantity: 99 },
        { menuItemId: "item_1k", quantity: 99 },
        { menuItemId: "item_1k", quantity: 99 },
        { menuItemId: "item_1k", quantity: 99 },
      ],
    }, { now: fixedNow });
    assert.strictEqual(resAllow.order.grandTotal, 495030);

    // Total > ₹500,000: 6 items with quantity 1 each at ₹90,000 = ₹540,000 -> DENY
    db.setDoc("shops/shop_active/menuItems/item_90k", {
      id: "item_90k",
      shopId: "shop_active",
      name: "90K Item",
      price: 90000,
      isAvailable: true,
    });
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [
          { menuItemId: "item_90k", quantity: 1 },
          { menuItemId: "item_90k", quantity: 1 },
          { menuItemId: "item_90k", quantity: 1 },
          { menuItemId: "item_90k", quantity: 1 },
          { menuItemId: "item_90k", quantity: 1 },
          { menuItemId: "item_90k", quantity: 1 },
        ],
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("exceeds allowable maximum limit of ₹500000")
    );
    pass("Order grand total ceiling (> ₹500,000 denied) strictly enforced");
  }

  // ─── Test 50: Decimal catalog pricing and exact paise arithmetic (Mandatory Correction 4) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // Shop with decimal delivery (25.50) and item with decimal base (49.50) + option (12.25)
    // Unit price = 49.50 + 12.25 = 61.75 (6175 paise)
    // Quantity = 3
    // Subtotal = 61.75 * 3 = 185.25 (18525 paise)
    // Delivery = 25.50 (2550 paise)
    // Grand Total = 185.25 + 25.50 = 210.75 (21075 paise)
    const request = {
      shopId: "shop_decimal",
      items: [
        {
          menuItemId: "item_decimal_pasta",
          quantity: 3,
          selectedOptions: [{ groupId: "grp_extra", optionId: "opt_herbs" }],
        },
      ],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    const stored = db.data.get(`orders/${res.orderId}`);

    assert.strictEqual(stored.items[0].price, 61.75);
    assert.strictEqual(stored.items[0].subtotal, 185.25);
    assert.strictEqual(stored.subtotal, 185.25);
    assert.strictEqual(stored.deliveryCharges, 25.50);
    assert.strictEqual(stored.grandTotal, 210.75);
    assert.strictEqual(stored.totalAmount, 210.75);
    assert.strictEqual(stored.totalItems, 3);
    pass("Decimal catalog pricing and exact integer paise arithmetic eliminate floating-point drift");
  }

  // ─── Test 51: Price Tampering Attack Matrix — All 16 fields verified in stored order ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // Attacker crafts a payload tampering with every conceivable financial field name
    const maliciousRequest = {
      shopId: "shop_active",
      // Root-level financial tampering attempts
      price: 0.01,
      unitPrice: 0.01,
      unitPriceOverride: 0.01,
      subtotal: 0.01,
      deliveryCharges: 0,
      deliveryCharge: 0,
      deliveryFee: 0,
      grandTotal: 0.01,
      totalAmount: 0.01,
      totalItems: 1,
      items: [
        {
          menuItemId: "item_custom_burger", // catalog: Regular is 130, Cheese is 25 -> unit 155
          quantity: 2, // authoritative subtotal = 155 * 2 = 310
          // Item-level financial tampering attempts
          price: 1,
          unitPrice: 1,
          unitPriceOverride: 1,
          subtotal: 2,
          totalPrice: 2,
          optionsDescription: "HACKED_FREE_OPTIONS_DESCRIPTION",
          selectedOptions: [
            {
              groupId: "grp_size",
              optionId: "opt_regular",
              // Option-level financial tampering attempts
              price: 0.1,
              fixedPrice: 0.1,
              priceAdjustment: 0.1,
              optionPrice: 0.1,
            },
            {
              groupId: "grp_cheese",
              optionId: "opt_extra_cheese",
              price: 0.2,
              fixedPrice: 0.2,
              priceAdjustment: 0.2,
              optionPrice: 0.2,
            },
          ],
        },
      ],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, maliciousRequest, { now: fixedNow });

    // CRITICAL SECURITY AUDIT CHECK: Inspect the actual stored document from Firestore
    const stored = db.data.get(`orders/${res.orderId}`);
    assert(stored, "Stored order must exist in Firestore");

    // 1. Authoritative item price (130 + 25 = 155), client price/unitPrice/unitPriceOverride ignored
    assert.strictEqual(stored.items[0].price, 155);

    // 2. Authoritative item subtotal (155 * 2 = 310), client subtotal/totalPrice ignored
    assert.strictEqual(stored.items[0].subtotal, 310);

    // 3. Authoritative option prices stored (130, 25), client option tampering ignored
    assert.strictEqual(stored.items[0].selectedOptions[0].price, 130);
    assert.strictEqual(stored.items[0].selectedOptions[1].price, 25);

    // 4. Authoritative optionsDescription generated from catalog names, client string ignored
    assert.strictEqual(stored.items[0].optionsDescription, "Regular · Extra Cheese");

    // 5. Authoritative order subtotal (310), client subtotal ignored
    assert.strictEqual(stored.subtotal, 310);

    // 6. Authoritative delivery charges (30 from shop_active), client deliveryCharges/deliveryCharge/deliveryFee ignored
    assert.strictEqual(stored.deliveryCharges, 30);

    // 7. Authoritative grandTotal (310 + 30 = 340), client grandTotal ignored
    assert.strictEqual(stored.grandTotal, 340);

    // 8. Authoritative totalAmount (340), client totalAmount ignored
    assert.strictEqual(stored.totalAmount, 340);

    // 9. Authoritative totalItems (2), client totalItems ignored
    assert.strictEqual(stored.totalItems, 2);

    pass("Price Tampering Attack Matrix: All 16 client financial fields ignored and stored Firestore order verified authoritative");
  }

  // ─── Test 52: Quantity security: NaN, Infinity, null, undefined, '3', 1.5, -1 rejected ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    const invalidQuantities = [NaN, Infinity, -Infinity, null, undefined, "3", "one", 1.5, -1, 0, 100];
    for (const badQ of invalidQuantities) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, {
          shopId: "shop_active",
          items: [{ menuItemId: "item_momos", quantity: badQ }],
        }, { now: fixedNow }),
        (err) => err.code === "invalid-argument",
        `Expected rejection for quantity: ${badQ}`
      );
    }
    pass("Quantity security: NaN, Infinity, null, undefined, strings, decimals, and out-of-bounds rejected");
  }

  // ─── Test 53: Catalog price mutation scenario / historical order immutability ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // Step 1: Initial catalog price of Momos is ₹80. Customer places Order 1.
    const res1 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    }, { now: fixedNow, _serverOrderId: "ORD_HISTORICAL_PRICE_1" });

    const stored1 = db.data.get("orders/ORD_HISTORICAL_PRICE_1");
    assert.strictEqual(stored1.items[0].price, 80);
    assert.strictEqual(stored1.subtotal, 80);
    assert.strictEqual(stored1.grandTotal, 110);

    // Step 2: Shopkeeper updates catalog price from ₹80 to ₹120
    db.setDoc("shops/shop_active/menuItems/item_momos", {
      id: "item_momos",
      shopId: "shop_active",
      name: "Steamed Momos",
      price: 120, // Updated catalog price!
      isAvailable: true,
    });

    // Step 3: Customer places Order 2 after catalog price change
    const res2 = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    }, { now: fixedNow, _serverOrderId: "ORD_HISTORICAL_PRICE_2" });

    const stored2 = db.data.get("orders/ORD_HISTORICAL_PRICE_2");
    assert.strictEqual(stored2.items[0].price, 120);
    assert.strictEqual(stored2.subtotal, 120);
    assert.strictEqual(stored2.grandTotal, 150);

    // Step 4: Verify Order 1 in Firestore STILL retains its original historical price of ₹80!
    const reReadOrder1 = db.data.get("orders/ORD_HISTORICAL_PRICE_1");
    assert.strictEqual(reReadOrder1.items[0].price, 80);
    assert.strictEqual(reReadOrder1.subtotal, 80);
    assert.strictEqual(reReadOrder1.grandTotal, 110);
    pass("Catalog price mutation scenario: Historical order pricing remains frozen; new orders reflect updated catalog");
  }

  // ─── Test 54: Stored order mathematical consistency invariants ──────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    const request = {
      shopId: "shop_active",
      items: [
        { menuItemId: "item_momos", quantity: 4 }, // 4 * 80 = 320
        { menuItemId: "item_coffee", quantity: 2, selectedOptions: [{ groupId: "grp_flavour", optionId: "opt_vanilla" }] }, // 2 * (50 + 15) = 130
        { menuItemId: "item_multi_pizza", quantity: 3, selectedOptions: [{ groupId: "grp_toppings", optionId: "opt_olives" }, { groupId: "grp_toppings", optionId: "opt_corn" }] }, // 3 * (200 + 30 + 25) = 765
      ],
    };

    const res = await processServerAuthoritativeOrder(db, authContext, request, { now: fixedNow });
    const stored = db.data.get(`orders/${res.orderId}`);

    // Invariant 1: sum(item subtotals) == subtotal
    const itemSubtotalsSum = stored.items.reduce((acc, it) => acc + it.subtotal, 0);
    assert.strictEqual(stored.subtotal, itemSubtotalsSum);
    assert.strictEqual(stored.subtotal, 1215); // 320 + 130 + 765

    // Invariant 2: subtotal + deliveryCharges == grandTotal
    assert.strictEqual(stored.grandTotal, stored.subtotal + stored.deliveryCharges);
    assert.strictEqual(stored.grandTotal, 1245); // 1215 + 30

    // Invariant 3: grandTotal == totalAmount
    assert.strictEqual(stored.grandTotal, stored.totalAmount);

    // Invariant 4: sum(item quantities) == totalItems
    const totalQty = stored.items.reduce((acc, it) => acc + it.quantity, 0);
    assert.strictEqual(stored.totalItems, totalQty);
    assert.strictEqual(stored.totalItems, 9); // 4 + 2 + 3

    pass("Stored order satisfies all 4 mathematical consistency invariants");
  }

  // ===========================================================================
  // PHASE 4.3 — REQUEST SHAPE, INPUT VALIDATION & SCHEMA HARDENING TEST SUITE
  // ===========================================================================

  // ─── Test 55: Request Body Shape & Primitive Type Confusion Matrix ──────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    const invalidBodies = [
      null,
      undefined,
      [],
      [1, 2, 3],
      "invalid string payload",
      12345,
      true,
      false,
    ];

    for (const body of invalidBodies) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, body, { now: fixedNow }),
        (err) => err.code === "invalid-argument" && err.message.includes("Invalid request payload: expected an object")
      );
    }
    pass("Test 55: Request body shape matrix rejects non-objects, arrays, primitives, and null");
  }

  // ─── Test 56: Prohibited Security & Identity Fields Matrix (Category A Rejection) ──
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    const prohibitedKeys = [
      "role",
      "admin",
      "isAdmin",
      "isShopkeeper",
      "isDeliveryPerson",
      "ownerUid",
      "claims",
      "internalFlags",
      "securityFlags",
      "serverTotal",
      "shopId2",
    ];

    // Sub-test A: Root-level prohibited security key injection
    for (const key of prohibitedKeys) {
      const hostilePayload = {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        [key]: true,
      };
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, hostilePayload, { now: fixedNow }),
        (err) => err.code === "invalid-argument" && err.message.includes(`Prohibited security/internal field detected: "${key}"`)
      );
    }

    // Sub-test B: Item-level prohibited security key injection
    for (const key of prohibitedKeys) {
      const hostileItemPayload = {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1, [key]: "evil_value" }],
      };
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, hostileItemPayload, { now: fixedNow }),
        (err) => err.code === "invalid-argument" && err.message.includes(`Prohibited field "${key}" detected in item`)
      );
    }

    // Sub-test C: Option-level prohibited security key injection
    for (const key of prohibitedKeys) {
      const hostileOptPayload = {
        shopId: "shop_active",
        items: [
          {
            menuItemId: "item_coffee",
            quantity: 1,
            selectedOptions: [{ groupId: "grp_flavour", optionId: "opt_vanilla", [key]: "evil_value" }],
          },
        ],
      };
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, hostileOptPayload, { now: fixedNow }),
        (err) => err.code === "invalid-argument" && err.message.includes(`Prohibited field "${key}" detected in option`)
      );
    }

    pass("Test 56: Prohibited security & identity fields strictly rejected across root, item, and option levels");
  }

  // ─── Test 57: ID Syntactic Validation Matrix (shopId, menuItemId, groupId, optionId) ──
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // 1. shopId invalid formats
    const badShopIds = [
      "",
      "   ",
      123,
      null,
      {},
      [],
      "../traversal",
      "shop/with/slashes",
      "shop@123",
      "shop with space",
      "a".repeat(65), // > 64 chars
    ];

    for (const badShop of badShopIds) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, {
          shopId: badShop,
          items: [{ menuItemId: "item_momos", quantity: 1 }],
        }, { now: fixedNow }),
        (err) => err.code === "invalid-argument"
      );
    }

    // 2. menuItemId invalid formats
    const badMenuItemIds = [
      "",
      "   ",
      123,
      null,
      {},
      [],
      "../../etc/passwd",
      "item/with/slashes",
      "item*deluxe",
      "item with space",
      "m".repeat(65),
    ];

    for (const badItem of badMenuItemIds) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, {
          shopId: "shop_active",
          items: [{ menuItemId: badItem, quantity: 1 }],
        }, { now: fixedNow }),
        (err) => err.code === "invalid-argument"
      );
    }

    // 3. groupId and optionId invalid formats
    const badGroupIds = ["", "  ", null, 123, "grp/evil", "g".repeat(65)];
    for (const badG of badGroupIds) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, {
          shopId: "shop_active",
          items: [{
            menuItemId: "item_coffee",
            quantity: 1,
            selectedOptions: [{ groupId: badG, optionId: "opt_vanilla" }],
          }],
        }, { now: fixedNow }),
        (err) => err.code === "invalid-argument"
      );
    }

    const badOptionIds = ["", "  ", null, 456, "opt/evil", "o".repeat(65)];
    for (const badO of badOptionIds) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, {
          shopId: "shop_active",
          items: [{
            menuItemId: "item_coffee",
            quantity: 1,
            selectedOptions: [{ groupId: "grp_flavour", optionId: badO }],
          }],
        }, { now: fixedNow }),
        (err) => err.code === "invalid-argument"
      );
    }

    pass("Test 57: ID syntactic validation matrix strictly rejects malformed IDs across shopId, menuItemId, groupId, optionId");
  }

  // ─── Test 58: Items Array & Item Structure Matrix ───────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    const invalidItemsPayloads = [
      null,
      123,
      "item_momos",
      {},
      true,
      false,
      [null],
      [123],
      ["string_item"],
      [{}],
      [{ menuItemId: "item_momos" }], // missing quantity
      [{ quantity: 1 }], // missing menuItemId
    ];

    for (const badItems of invalidItemsPayloads) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, {
          shopId: "shop_active",
          items: badItems,
        }, { now: fixedNow }),
        (err) => err.code === "invalid-argument"
      );
    }

    pass("Test 58: Items array & item structure matrix rejects malformed arrays, non-objects, and missing fields");
  }

  // ─── Test 59: Nested Option Structural Validation Matrix ────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    const invalidOptionsPayloads = [
      "opt_vanilla", // non-array
      123,
      {},
      true,
      [null],
      [123],
      ["opt_vanilla"],
      [{}],
      [{ groupId: "grp_flavour" }], // missing optionId
      [{ optionId: "opt_vanilla" }], // missing groupId
    ];

    for (const badOpts of invalidOptionsPayloads) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, {
          shopId: "shop_active",
          items: [{
            menuItemId: "item_coffee",
            quantity: 1,
            selectedOptions: badOpts,
          }],
        }, { now: fixedNow }),
        (err) => err.code === "invalid-argument"
      );
    }

    // Exceeding MAX_OPTIONS_PER_ITEM (20)
    const twentyOneOptions = [];
    for (let i = 1; i <= 21; i++) {
      twentyOneOptions.push({ groupId: `grp_${i}`, optionId: `opt_${i}` });
    }
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{
          menuItemId: "item_coffee",
          quantity: 1,
          selectedOptions: twentyOneOptions,
        }],
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("Too many selectedOptions")
    );

    pass("Test 59: Nested option structural validation rejects non-arrays, primitives, missing keys, and oversized option sets");
  }

  // ─── Test 60: User Text Fields Validation & No Silent Truncation (Mandatory Correction 1) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // 1. customerName: wrong type, oversized, control characters, null byte
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        customerName: 12345,
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("expected a string")
    );

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        customerName: null,
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("null is not a valid string")
    );

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        customerName: "A".repeat(101), // > MAX_CUSTOMER_NAME_LENGTH
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("exceeds maximum allowable length of 100")
    );

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        customerName: "Alice\x00Smith", // null byte
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("disallowed control characters or null bytes")
    );

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        customerName: "Alice\x07Smith", // BEL control char
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("disallowed control characters or null bytes")
    );

    // 2. customerPhone: wrong type, oversized, control characters
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        customerPhone: 9876543210, // number instead of string
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("expected a string")
    );

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        customerPhone: "1".repeat(21), // > MAX_CUSTOMER_PHONE_LENGTH
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("exceeds maximum allowable length of 20")
    );

    // 3. specialInstructions: wrong type, oversized, control characters
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        specialInstructions: 999,
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        specialInstructions: "E".repeat(501), // > 500 chars
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("exceeds maximum allowable length of 500")
    );

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        specialInstructions: "Extra spicy\x00Injection",
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );

    // 4. deliveryNote: wrong type, oversized, control characters
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        deliveryNote: true,
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );

    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        deliveryNote: "D".repeat(201), // > 200 chars
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes("exceeds maximum allowable length of 200")
    );

    // 5. VALID TEXT PRESERVATION (NO SILENT TRUNCATION!)
    // If input is within limits, it MUST be preserved exactly as-is without .slice() mutation
    const exact100Name = "A".repeat(100);
    const exact20Phone = "+91-9876543210-ABC"; // exactly 18 chars <= 20
    const exact500Instructions = "Please make it extra spicy, add green chutney and oregano. ".repeat(8).slice(0, 500);
    const exact200DeliveryNote = "Hostel 3, Room 402, Block B, Bennett University, Greater Noida. ".repeat(3).slice(0, 200);

    const validTextRes = await processServerAuthoritativeOrder(db, { uid: "user_unregistered_no_doc" }, {
      shopId: "shop_active",
      customerName: exact100Name,
      customerPhone: exact20Phone,
      specialInstructions: exact500Instructions,
      deliveryNote: exact200DeliveryNote,
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    }, { now: fixedNow });

    assert.strictEqual(validTextRes.order.customerName, exact100Name, "customerName must be preserved exactly as-is");
    assert.strictEqual(validTextRes.order.customerPhone, exact20Phone, "customerPhone must be preserved exactly as-is");
    assert.strictEqual(validTextRes.order.specialInstructions, exact500Instructions, "specialInstructions must be preserved exactly as-is");
    assert.strictEqual(validTextRes.order.deliveryNote, exact200DeliveryNote, "deliveryNote must be preserved exactly as-is");

    pass("Test 60: User text fields strictly validated without silent truncation; invalid types/lengths/controls rejected");
  }

  // ─── Test 61: Order Placement Method (orderMethod) Validation (Mandatory Correction 2) ─
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // 1. All valid supported production values succeed:
    const validModes = ["app", "whatsapp", "wa", "in_app", "both"];
    for (const mode of validModes) {
      const res = await processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        orderMethod: mode,
        items: [{ menuItemId: "item_momos", quantity: 1 }],
      }, { now: fixedNow });

      if (mode === "whatsapp" || mode === "wa") {
        assert.strictEqual(res.order.orderMethod, "whatsapp");
      } else if (mode === "both") {
        assert.strictEqual(res.order.orderMethod, "both");
      } else {
        assert.strictEqual(res.order.orderMethod, "app");
      }
    }

    // 2. Omitted orderMethod defaults to "app":
    const defaultRes = await processServerAuthoritativeOrder(db, authContext, {
      shopId: "shop_active",
      items: [{ menuItemId: "item_momos", quantity: 1 }],
    }, { now: fixedNow });
    assert.strictEqual(defaultRes.order.orderMethod, "app");

    // 3. Invalid or unknown orderMethod values rejected:
    const badModes = [
      "telepathy",
      "web",
      "unknown",
      "",
      "   ",
      123,
      true,
      false,
      null,
      {},
      [],
    ];

    for (const badMode of badModes) {
      await assert.rejects(
        async () => processServerAuthoritativeOrder(db, authContext, {
          shopId: "shop_active",
          orderMethod: badMode,
          items: [{ menuItemId: "item_momos", quantity: 1 }],
        }, { now: fixedNow }),
        (err) => err.code === "invalid-argument" && (err.message.includes("Invalid orderMethod") || err.message.includes("expected a string"))
      );
    }

    pass("Test 61: OrderMethod strictly validated against actual production values; unknown values/types rejected");
  }

  // ─── Test 62: Unknown Field Policy: Category A vs Category B vs Category C (Mandatory Correction 3) ──
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // Category A: Prohibited security field -> REJECT
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        ownerUid: "attacker_uid",
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument" && err.message.includes('Prohibited security/internal field detected: "ownerUid"')
    );

    // Category B: Known legacy client convenience field (client financial / metadata) -> IGNORED
    // Category C: Arbitrary unknown client fields -> NEVER COPIED TO finalOrderDoc
    const requestWithMixedFields = {
      shopId: "shop_active",
      items: [
        {
          menuItemId: "item_momos",
          quantity: 2,
          // Category B inside item:
          price: 1, // Client lies about item price
          subtotal: 2,
          name: "Client Overridden Name",
          imageUrl: "http://fake.url/img.png",
          cartKey: "fake_cart_key",
          // Category C inside item:
          extraItemNotes: "don't put onion",
        },
      ],
      // Category B at root:
      subtotal: 10,
      grandTotal: 10,
      totalAmount: 10,
      totalItems: 1,
      deliveryCharges: 0,
      status: "delivered",
      rejectionReason: "none",
      // Category C at root:
      clientAppVersion: "2.4.1",
      deviceTelemetry: { os: "Android", model: "Pixel 7" },
      sessionTrackingUuid: "9f823-1123-5566",
    };

    const res = await processServerAuthoritativeOrder(db, authContext, requestWithMixedFields, {
      now: fixedNow,
      _serverOrderId: "ORD_POLICY_TEST_1",
    });

    const storedDoc = db.data.get("orders/ORD_POLICY_TEST_1");
    assert(storedDoc, "Stored document must exist");

    // Verify Category B had NO influence on server authority:
    assert.strictEqual(storedDoc.subtotal, 160, "Authoritative subtotal (80 * 2)");
    assert.strictEqual(storedDoc.grandTotal, 190, "Authoritative grandTotal (160 + 30)");
    assert.strictEqual(storedDoc.status, "placed", "Authoritative status strictly 'placed'");

    // Verify Category C fields were NEVER copied into finalOrderDoc:
    assert.strictEqual(storedDoc.clientAppVersion, undefined, "Category C root field clientAppVersion must NOT be stored");
    assert.strictEqual(storedDoc.deviceTelemetry, undefined, "Category C root field deviceTelemetry must NOT be stored");
    assert.strictEqual(storedDoc.sessionTrackingUuid, undefined, "Category C root field sessionTrackingUuid must NOT be stored");
    assert.strictEqual(storedDoc.items[0].extraItemNotes, undefined, "Category C item field extraItemNotes must NOT be stored");

    // Verify exact keys in stored order document match official server schema whitelist
    const expectedKeys = new Set([
      "orderId",
      "shopId",
      "shopName",
      "customerId",
      "customerName",
      "customerPhone",
      "items",
      "subtotal",
      "deliveryCharges",
      "totalItems",
      "grandTotal",
      "totalAmount",
      "specialInstructions",
      "deliveryNote",
      "status",
      "rejectionReason",
      "orderMethod",
      "createdAt",
      "updatedAt",
      "acceptDeadline",
    ]);

    for (const key of Object.keys(storedDoc)) {
      assert(expectedKeys.has(key), `Unexpected key "${key}" found in stored order document!`);
    }

    pass("Test 62: Unknown fields policy verified: Category A rejected, Category B ignored, Category C never copied to Firestore");
  }

  // ─── Test 63: Compound Attack Vectors Matrix ─────────────────────────────────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified" };

    // 1. Valid request + 1 malformed field (malformed shopId)
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: 12345,
        items: [{ menuItemId: "item_momos", quantity: 1 }],
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );

    // 2. Valid request + multiple malformed fields (shopId number + negative quantity + oversized note)
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        deliveryNote: "A".repeat(500),
        items: [{ menuItemId: "item_momos", quantity: -1 }],
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );

    // 3. Valid request + security field injection
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{ menuItemId: "item_momos", quantity: 1 }],
        isAdmin: true,
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );

    // 4. Valid request + malformed nested option (optionId contains directory traversal)
    await assert.rejects(
      async () => processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        items: [{
          menuItemId: "item_coffee",
          quantity: 1,
          selectedOptions: [{ groupId: "grp_flavour", optionId: "../traversal" }],
        }],
      }, { now: fixedNow }),
      (err) => err.code === "invalid-argument"
    );

    pass("Test 63: Compound attack vectors strictly rejected across multiple simultaneous failure modes");
  }

  // ─── Test 64: Pre-Database Shielding Proof (Zero Firestore Reads on Malformed Requests) ─
  {
    const authContext = { uid: "cust_verified" };

    const hostileInputs = [
      { shopId: "../invalid_path", items: [{ menuItemId: "item_momos", quantity: 1 }] },
      { shopId: "shop_active", items: [] },
      { shopId: "shop_active", items: [{ menuItemId: "../invalid_item", quantity: 1 }] },
      { shopId: "shop_active", items: [{ menuItemId: "item_momos", quantity: 0 }] },
      { shopId: "shop_active", items: [{ menuItemId: "item_momos", quantity: 100 }] },
      { shopId: "shop_active", items: [{ menuItemId: "item_momos", quantity: 1 }], role: "admin" },
      { shopId: "shop_active", items: [{ menuItemId: "item_momos", quantity: 1 }], specialInstructions: "X".repeat(501) },
      { shopId: "shop_active", items: [{ menuItemId: "item_momos", quantity: 1 }], orderMethod: "telepathy" },
    ];

    for (const badReq of hostileInputs) {
      const freshDb = createSeededFirestore();
      await assert.rejects(
        async () => processServerAuthoritativeOrder(freshDb, authContext, badReq, { now: fixedNow }),
        (err) => err.code === "invalid-argument"
      );
      assert.strictEqual(
        freshDb.readCounts.size,
        0,
        `Zero Firestore reads must occur on structurally invalid request: ${JSON.stringify(badReq)}`
      );
    }

    pass("Test 64: Pre-database shielding verified: Zero Firestore reads performed on malformed requests");
  }

  // ─── Test 65: Comprehensive Positive Regression Across All Order Methods ─────
  {
    const db = createSeededFirestore();
    const authContext = { uid: "cust_verified", phone: "+919876543210" };

    const testScenarios = [
      { mode: "app", expected: "app" },
      { mode: "whatsapp", expected: "whatsapp" },
      { mode: "both", expected: "both" },
    ];

    for (const sc of testScenarios) {
      const orderRes = await processServerAuthoritativeOrder(db, authContext, {
        shopId: "shop_active",
        orderMethod: sc.mode,
        customerName: "Ayush Goyal",
        specialInstructions: "Please pack properly and provide tissue napkins.",
        deliveryNote: "Hostel 2 front porch",
        items: [
          { menuItemId: "item_momos", quantity: 2 },
          {
            menuItemId: "item_coffee",
            quantity: 1,
            selectedOptions: [{ groupId: "grp_flavour", optionId: "opt_vanilla" }],
          },
        ],
      }, { now: fixedNow });

      assert(orderRes.success);
      assert(orderRes.orderId.startsWith("ORD_"));
      assert.strictEqual(orderRes.order.orderMethod, sc.expected);
      assert.strictEqual(orderRes.order.customerName, "Rajat Sharma", "Authoritative profile name from users collection used");
      assert.strictEqual(orderRes.order.customerPhone, "9876543210");
      assert.strictEqual(orderRes.order.specialInstructions, "Please pack properly and provide tissue napkins.");
      assert.strictEqual(orderRes.order.deliveryNote, "Hostel 2 front porch");
      assert.strictEqual(orderRes.order.status, "placed");
      assert.strictEqual(orderRes.order.subtotal, 225); // (80*2) + (50+15) = 160 + 65 = 225
      assert.strictEqual(orderRes.order.deliveryCharges, 30);
      assert.strictEqual(orderRes.order.grandTotal, 255);
      assert.strictEqual(orderRes.order.totalItems, 3);
    }

    pass("Test 65: Positive regression succeeded across all supported order methods with valid complex payloads");
  }

  console.log("==================================================");
  console.log(`ALL ${passed}/${passed} SERVER-AUTHORITATIVE TESTS PASSED!`);
  console.log("==================================================");
}

runTests().catch((err) => {
  console.error("❌ Test failed with error:", err);
  process.exit(1);
});
