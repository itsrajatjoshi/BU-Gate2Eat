/**
 * YummBU — Backend Auth Service Unit Tests
 * 
 * Verifies all 14 server-side authentication, role-resolution,
 * UID strategy, and custom token generation security invariants.
 */

const assert = require("assert");
const {
  normalizeCanonicalPhone,
  canonicalizeShopId,
  resolveIdentityForPhone,
  createCustomTokenForPhone,
  SERVER_ADMIN_PHONES,
  SERVER_SHOPKEEPER_PHONE_MAP,
  CANONICAL_ROLES,
  CANONICAL_ACCOUNT_STATUSES,
  buildCanonicalClaims,
} = require("./auth_service");

// ─── Mock Firebase Auth for Offline Testing ─────────────────────────────────
class MockAdminAuth {
  constructor() {
    this.users = new Map();
    this.customClaims = new Map();
    this.customTokensCreated = [];
  }

  async getUser(uid) {
    if (this.users.has(uid)) {
      return this.users.get(uid);
    }
    const err = new Error("User not found");
    err.code = "auth/user-not-found";
    throw err;
  }

  async createUser(properties) {
    this.users.set(properties.uid, {
      uid: properties.uid,
      phoneNumber: properties.phoneNumber,
      displayName: properties.displayName,
    });
    return this.users.get(properties.uid);
  }

  async setCustomUserClaims(uid, claims) {
    this.customClaims.set(uid, { ...claims });
  }

  async createCustomToken(uid, claims) {
    const token = `mock_custom_token_${uid}_${Date.now()}`;
    this.customTokensCreated.push({ uid, claims, token });
    return token;
  }
}

async function runTests() {
  console.log("==================================================");
  console.log("RUNNING BACKEND AUTH SERVICE TESTS (Step 5)");
  console.log("==================================================");

  let passed = 0;
  let total = 0;

  function test(name, fn) {
    total++;
    try {
      fn();
      console.log(`✅ [PASS] ${total}. ${name}`);
      passed++;
    } catch (err) {
      console.error(`❌ [FAIL] ${total}. ${name}`);
      console.error(err);
      process.exit(1);
    }
  }

  async function testAsync(name, fn) {
    total++;
    try {
      await fn();
      console.log(`✅ [PASS] ${total}. ${name}`);
      passed++;
    } catch (err) {
      console.error(`❌ [FAIL] ${total}. ${name}`);
      console.error(err);
      process.exit(1);
    }
  }

  // 1. Valid customer phone resolves to customer
  test("1. Valid customer phone resolves to customer role and deterministic UID", () => {
    const identity = resolveIdentityForPhone("9876543210");
    assert.strictEqual(identity.role, "customer");
    assert.strictEqual(identity.uid, "phone_9876543210");
    assert.strictEqual(identity.shopId, undefined);
  });

  // 2. Valid shopkeeper phone resolves to shopkeeper with canonical shopId
  test("2. Valid shopkeeper phone resolves to shopkeeper with canonical shopId", () => {
    const identity = resolveIdentityForPhone("8000383993");
    assert.strictEqual(identity.role, "shopkeeper");
    assert.strictEqual(identity.shopId, "rajat_shop");
    assert.strictEqual(identity.customerId, undefined);
    assert.strictEqual(identity.uid, "phone_8000383993");
  });

  // 3. Valid admin phone resolves to admin
  test("3. Valid admin phone resolves to admin with role claim and NO shopId", () => {
    const identity = resolveIdentityForPhone("8078643910");
    assert.strictEqual(identity.role, "admin");
    assert.strictEqual(identity.shopId, undefined);
    assert.strictEqual(identity.customerId, undefined);
    assert.strictEqual(identity.uid, "phone_8078643910");
  });

  // 4. Valid unknown 10-digit phone resolves to customer policy
  test("4. Unknown valid 10-digit phone safely resolves to customer role", () => {
    const identity = resolveIdentityForPhone("9123456780");
    assert.strictEqual(identity.role, "customer");
    assert.strictEqual(identity.uid, "phone_9123456780");
  });

  // 5. Malformed phone numbers are rejected
  test("5. Malformed phone numbers are rejected with clear error", () => {
    assert.throws(() => normalizeCanonicalPhone(""), /Invalid phone input/);
    assert.throws(() => normalizeCanonicalPhone(null), /Invalid phone input/);
    assert.throws(() => normalizeCanonicalPhone("12345"), /Malformed phone number/);
    assert.throws(() => normalizeCanonicalPhone("9876543210123"), /Malformed phone number/);
    assert.throws(() => normalizeCanonicalPhone("98765ABCDE"), /Malformed phone number/);
  });

  // 5b. Phone normalization correctly handles prefixes and formatting
  test("5b. Phone normalization strips +91, 91, 0 prefix, spaces, and dashes", () => {
    assert.strictEqual(normalizeCanonicalPhone("+91 80003-83993"), "8000383993");
    assert.strictEqual(normalizeCanonicalPhone("918000383993"), "8000383993");
    assert.strictEqual(normalizeCanonicalPhone("08000383993"), "8000383993");
  });

  // 6. Customer receives customer role claim
  test("6. Customer receives customer role claim strictly without redundant customerId", () => {
    const identity = resolveIdentityForPhone("9876543210");
    assert.deepStrictEqual(identity.claims, {
      role: "customer",
    });
  });

  // 7. Shopkeeper receives correct canonical shopId
  test("7. Shopkeeper receives correct canonical shopId (including aliases)", () => {
    const identityA = resolveIdentityForPhone("8000383993");
    assert.deepStrictEqual(identityA.claims, {
      role: "shopkeeper",
      shopId: "rajat_shop",
    });

    // Test alias resolution
    assert.strictEqual(canonicalizeShopId("up16_queens"), "up16_coffee_queen");
    assert.strictEqual(canonicalizeShopId("rajat_shop"), "rajat_shop");
  });

  // 8. Admin does not receive arbitrary shopId
  test("8. Admin claims never contain shopId", () => {
    const identity = resolveIdentityForPhone("8078643910");
    assert.deepStrictEqual(identity.claims, {
      role: "admin",
    });
    assert.strictEqual(identity.claims.shopId, undefined);
  });

  // 9. Client cannot supply/override role
  await testAsync("9. Client cannot supply or override role (Security Violation)", async () => {
    const mockAuth = new MockAdminAuth();
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("9876543210", {
          role: "admin",
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role/
    );
  });

  // 10. Client cannot supply/override shopId
  await testAsync("10. Client cannot supply or override shopId (Security Violation)", async () => {
    const mockAuth = new MockAdminAuth();
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("9876543210", {
          shopId: "rajat_shop",
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role/
    );
  });

  // 11. Client cannot supply/override customerId
  await testAsync("11. Client cannot supply or override customerId (Security Violation)", async () => {
    const mockAuth = new MockAdminAuth();
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("9876543210", {
          customerId: "cust_other_user",
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role/
    );
  });

  // 12. Deterministic UID does not create duplicates
  test("12. Deterministic UID strategy produces identical UID for the same phone", () => {
    const id1 = resolveIdentityForPhone("9876543210");
    const id2 = resolveIdentityForPhone("+91-98765-43210");
    assert.strictEqual(id1.uid, "phone_9876543210");
    assert.strictEqual(id2.uid, "phone_9876543210");
    assert.strictEqual(id1.uid, id2.uid);
  });

  // 13. Custom token generation occurs with server-trusted claims via Admin SDK
  await testAsync("13. Custom token creation sets server-trusted claims on Firebase user", async () => {
    const mockAuth = new MockAdminAuth();
    
    // Customer
    const custResult = await createCustomTokenForPhone("9876543210", { authInstance: mockAuth });
    assert.strictEqual(custResult.uid, "phone_9876543210");
    assert.strictEqual(custResult.role, "customer");
    assert(custResult.customToken.startsWith("mock_custom_token_phone_9876543210"));
    assert.deepStrictEqual(mockAuth.customClaims.get("phone_9876543210"), {
      role: "customer",
    });

    // Shopkeeper
    const shopResult = await createCustomTokenForPhone("8000383993", { authInstance: mockAuth });
    assert.strictEqual(shopResult.uid, "phone_8000383993");
    assert.strictEqual(shopResult.role, "shopkeeper");
    assert.strictEqual(shopResult.shopId, "rajat_shop");
    assert.deepStrictEqual(mockAuth.customClaims.get("phone_8000383993"), {
      role: "shopkeeper",
      shopId: "rajat_shop",
    });

    // Admin
    const adminResult = await createCustomTokenForPhone("8078643910", { authInstance: mockAuth });
    assert.strictEqual(adminResult.uid, "phone_8078643910");
    assert.strictEqual(adminResult.role, "admin");
    assert.strictEqual(adminResult.shopId, undefined);
    assert.deepStrictEqual(mockAuth.customClaims.get("phone_8078643910"), {
      role: "admin",
    });
  });

  // 14. Returned payload contains zero sensitive internal keys or secrets
  await testAsync("14. Returned payload contains only safe identity fields, zero secrets", async () => {
    const mockAuth = new MockAdminAuth();
    const result = await createCustomTokenForPhone("9876543210", { authInstance: mockAuth });
    const keys = Object.keys(result);
    assert(keys.includes("customToken"));
    assert(keys.includes("uid"));
    assert(keys.includes("role"));
    assert(!keys.includes("privateKey"));
    assert(!keys.includes("client_secret"));
    assert(!keys.includes("serviceAccount"));
  });

  // 15. Canonical roles defines exactly customer, shopkeeper, admin
  test("15. CANONICAL_ROLES defines exactly customer, shopkeeper, admin", () => {
    assert.deepStrictEqual(Array.from(CANONICAL_ROLES), ["customer", "shopkeeper", "admin"]);
  });

  // 16. Canonical account statuses defines active and deactivated
  test("16. CANONICAL_ACCOUNT_STATUSES defines active and deactivated", () => {
    assert.deepStrictEqual(Array.from(CANONICAL_ACCOUNT_STATUSES), ["active", "deactivated"]);
  });

  // 17. buildCanonicalClaims creates admin claims strictly omitting shopId
  test("17. buildCanonicalClaims creates admin claims strictly omitting shopId", () => {
    const adminClaims = buildCanonicalClaims("admin");
    assert.strictEqual(adminClaims.role, "admin");
    assert.strictEqual(adminClaims.shopId, undefined);
    assert.strictEqual(adminClaims.customerId, undefined);
  });

  // 18. buildCanonicalClaims rejects shopkeeper role without valid shopId
  test("18. buildCanonicalClaims rejects shopkeeper role without valid shopId", () => {
    assert.throws(
      () => buildCanonicalClaims("shopkeeper", {}),
      /Shopkeeper role strictly requires a valid, authoritative shopId assignment/
    );
    assert.throws(
      () => buildCanonicalClaims("shopkeeper", { shopId: "" }),
      /Shopkeeper role strictly requires a valid, authoritative shopId assignment/
    );
    const validClaims = buildCanonicalClaims("shopkeeper", { shopId: "rajat_shop" });
    assert.strictEqual(validClaims.role, "shopkeeper");
    assert.strictEqual(validClaims.shopId, "rajat_shop");
  });

  // 19. buildCanonicalClaims rejects invalid or unrecognized roles
  test("19. buildCanonicalClaims rejects invalid or unrecognized roles", () => {
    assert.throws(() => buildCanonicalClaims("superadmin"), /Invalid canonical role/);
    assert.throws(() => buildCanonicalClaims("moderator"), /Invalid canonical role/);
    assert.throws(() => buildCanonicalClaims(""), /Invalid role input/);
    assert.throws(() => buildCanonicalClaims(null), /Invalid role input/);
  });

  // 20. buildCanonicalClaims supports account deactivation status
  test("20. buildCanonicalClaims supports account deactivation status", () => {
    const deactivatedCustomer = buildCanonicalClaims("customer", {
      status: "deactivated",
    });
    assert.strictEqual(deactivatedCustomer.role, "customer");
    assert.strictEqual(deactivatedCustomer.status, "deactivated");
  });

  // 21. Client cannot supply or override status or accountStatus (Security Violation)
  await testAsync("21. Client cannot supply or override status or accountStatus (Security Violation)", async () => {
    const mockAuth = new MockAdminAuth();
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("9876543210", {
          status: "active",
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role, shopId, customerId, status, or claims/
    );
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("9876543210", {
          accountStatus: "active",
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role, shopId, customerId, status, or claims/
    );
  });

  // 22. Client cannot supply or override admin or isAdmin flag (Security Violation)
  await testAsync("22. Client cannot supply or override admin or isAdmin flag (Security Violation)", async () => {
    const mockAuth = new MockAdminAuth();
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("9876543210", {
          admin: true,
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role/
    );
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("9876543210", {
          isAdmin: true,
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role/
    );
  });

  // 23. Client cannot supply or override isShopkeeper flag (Security Violation)
  await testAsync("23. Client cannot supply or override isShopkeeper flag (Security Violation)", async () => {
    const mockAuth = new MockAdminAuth();
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("9876543210", {
          isShopkeeper: true,
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role/
    );
  });

  // 24. Shopkeeper phone cannot be granted cross-shop assignment via client options
  await testAsync("24. Shopkeeper phone cannot be granted cross-shop assignment via client options", async () => {
    const mockAuth = new MockAdminAuth();
    // Phone 8000383993 is Rajat Shop; attempting to inject nayan_shop
    await assert.rejects(
      async () => {
        await createCustomTokenForPhone("8000383993", {
          shopId: "nayan_shop",
          authInstance: mockAuth,
        });
      },
      /Security Violation: Client cannot supply or override role, shopId, customerId, status, or claims/
    );
  });

  console.log("==================================================");
  console.log(`ALL ${passed}/${total} BACKEND AUTH SERVICE TESTS PASSED!`);
  console.log("==================================================");
}

runTests().catch(err => {
  console.error("Test suite encountered unexpected error:", err);
  process.exit(1);
});
