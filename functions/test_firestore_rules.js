/**
 * YummBU / BU Gate2Eat — Firestore Security Rules Unit Tests
 * 
 * Checkpoint 3.2: Shops / Categories / Menu Rules & Tenant Isolation
 * 
 * Tests against live Firebase Firestore Emulator using @firebase/rules-unit-testing.
 * Proves that database-level authorization enforces:
 *  - Public catalog browsing where intended
 *  - Customer & anonymous write denial across all catalog tiers
 *  - Strict tenant boundary: shopkeepers write ONLY to their assigned shopId
 *  - Cross-tenant attack rejection (Shopkeeper A -> Shopkeeper B denied)
 *  - Shop ownership / shopId immutability (cannot mutate shopId)
 *  - Admin authority restricted strictly to canonical custom claim role == 'admin'
 *  - Default-deny preserved on all protected & unconfigured collections
 */

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'bugate2eat-rules-test';
const RULES_PATH = path.resolve(__dirname, '../firestore.rules');

let testEnv;
let unauthDb;
let customerDb;
let customer2Db;
let shopkeeperADb;
let shopkeeperBDb;
let adminDb;
let attackerDb;
let customerWithAdminPhoneDb;
let shopkeeperWithAdminPhoneDb;
let userWithAdminFlagDb;
let userWithAdminPhoneOnlyDb;
let userWithMissingRoleDb;
let shopkeeperMissingShopIdDb;
let shopkeeperEmptyShopIdDb;

let passCount = 0;
let totalTests = 0;

function reportTest(name, passed) {
  totalTests++;
  if (passed) {
    passCount++;
    console.log(`  ✅ [PASS] ${name}`);
  } else {
    console.error(`  ❌ [FAIL] ${name}`);
  }
}

async function setup() {
  const rules = fs.readFileSync(RULES_PATH, 'utf8');
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: rules,
    },
  });

  // 1. Unauthenticated (Anonymous) context
  unauthDb = testEnv.unauthenticatedContext().firestore();

  // 2. Customer A
  customerDb = testEnv.authenticatedContext('customer_a', {
    role: 'customer',
  }).firestore();

  // 3. Customer B
  customer2Db = testEnv.authenticatedContext('customer_b', {
    role: 'customer',
  }).firestore();

  // 4. Shopkeeper A (shop_a tenant)
  shopkeeperADb = testEnv.authenticatedContext('shopkeeper_a', {
    role: 'shopkeeper',
    shopId: 'shop_a',
  }).firestore();

  // 5. Shopkeeper B (shop_b tenant)
  shopkeeperBDb = testEnv.authenticatedContext('shopkeeper_b', {
    role: 'shopkeeper',
    shopId: 'shop_b',
  }).firestore();

  // 6. Platform Administrator (canonical role: admin)
  adminDb = testEnv.authenticatedContext('admin_uid', {
    role: 'admin',
  }).firestore();

  // 7. Attacker context (direct API caller attempting privilege escalation)
  attackerDb = testEnv.authenticatedContext('attacker_uid', {
    role: 'customer',
  }).firestore();

  // 8. Customer with admin-looking phone data
  customerWithAdminPhoneDb = testEnv.authenticatedContext('cust_with_admin_phone', {
    role: 'customer',
    phone_number: '+918078643910',
    phone: '8078643910',
  }).firestore();

  // 9. Shopkeeper with admin-looking phone data
  shopkeeperWithAdminPhoneDb = testEnv.authenticatedContext('shop_with_admin_phone', {
    role: 'shopkeeper',
    shopId: 'shop_a',
    phone_number: '+918078643910',
    phone: '8078643910',
  }).firestore();

  // 10. Authenticated user with admin: true flag but role != admin
  userWithAdminFlagDb = testEnv.authenticatedContext('user_admin_flag', {
    admin: true,
    role: 'customer',
  }).firestore();

  // 11. Authenticated user with former admin phone but missing role claim
  userWithAdminPhoneOnlyDb = testEnv.authenticatedContext('user_admin_phone_only', {
    phone_number: '+918078643910',
    phone: '8078643910',
  }).firestore();

  // 12. Authenticated user with completely missing role claim
  userWithMissingRoleDb = testEnv.authenticatedContext('user_missing_role', {}).firestore();

  // 13. Shopkeeper with missing shopId claim
  shopkeeperMissingShopIdDb = testEnv.authenticatedContext('shopkeeper_missing_shop', {
    role: 'shopkeeper',
  }).firestore();

  // 14. Shopkeeper with empty string shopId claim
  shopkeeperEmptyShopIdDb = testEnv.authenticatedContext('shopkeeper_empty_shop', {
    role: 'shopkeeper',
    shopId: '',
  }).firestore();

  // Seed initial test documents via security rules bypass
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const adminFs = context.firestore();

    // Seed shop documents
    await adminFs.collection('shops').doc('shop_a').set({
      name: 'Shop A',
      id: 'shop_a',
      shopId: 'shop_a',
      isActive: true,
      isClosedOverride: false,
    });
    await adminFs.collection('shops').doc('shop_b').set({
      name: 'Shop B',
      id: 'shop_b',
      shopId: 'shop_b',
      isActive: true,
      isClosedOverride: false,
    });

    // Seed categories
    await adminFs.collection('shops').doc('shop_a').collection('categories').doc('cat_a1').set({
      name: 'Momos',
      shopId: 'shop_a',
      isActive: true,
      sortOrder: 1,
    });
    await adminFs.collection('shops').doc('shop_b').collection('categories').doc('cat_b1').set({
      name: 'Pizzas',
      shopId: 'shop_b',
      isActive: true,
      sortOrder: 1,
    });

    // Seed menu items
    await adminFs.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').set({
      name: 'Steam Momos',
      price: 60,
      shopId: 'shop_a',
      isAvailable: true,
    });
    await adminFs.collection('shops').doc('shop_a').collection('menuItems').doc('item_to_delete').set({
      name: 'Temporary Item',
      price: 50,
      shopId: 'shop_a',
      isAvailable: true,
    });
    await adminFs.collection('shops').doc('shop_b').collection('menuItems').doc('item_b1').set({
      name: 'Margherita Pizza',
      price: 150,
      shopId: 'shop_b',
      isAvailable: true,
    });
  });
}

async function runRulesSecuritySuite() {
  console.log('=================================================================');
  console.log('  CHECKPOINT 3.2: SHOPS / CATEGORIES / MENU RULES SUITE          ');
  console.log('=================================================================\n');

  // ═════════════════════════════════════════════════════════════════════
  // SECTION 9 MANDATORY TESTS (1 - 37)
  // ═════════════════════════════════════════════════════════════════════

  console.log('--- Phase 3.2: Shops Tier Tests (1 - 15) ---');

  // 1. Anonymous shop read -> ALLOW
  try {
    await assertSucceeds(unauthDb.collection('shops').doc('shop_a').get());
    reportTest('Test 1: Anonymous shop read -> ALLOW', true);
  } catch (e) {
    reportTest('Test 1: Anonymous shop read -> ALLOW', false);
  }

  // 2. Customer shop read -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('shops').doc('shop_a').get());
    reportTest('Test 2: Customer shop read -> ALLOW', true);
  } catch (e) {
    reportTest('Test 2: Customer shop read -> ALLOW', false);
  }

  // 3. Shopkeeper shop read -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').get());
    reportTest('Test 3: Shopkeeper shop read -> ALLOW', true);
  } catch (e) {
    reportTest('Test 3: Shopkeeper shop read -> ALLOW', false);
  }

  // 4. Admin shop read -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').get());
    reportTest('Test 4: Admin shop read -> ALLOW', true);
  } catch (e) {
    reportTest('Test 4: Admin shop read -> ALLOW', false);
  }

  // 5. Anonymous shop create -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_anon_new').set({ name: 'Hacked Shop' }));
    reportTest('Test 5: Anonymous shop create -> DENY', true);
  } catch (e) {
    reportTest('Test 5: Anonymous shop create -> DENY', false);
  }

  // 6. Anonymous shop update -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_a').update({ name: 'Hacked Shop A' }));
    reportTest('Test 6: Anonymous shop update -> DENY', true);
  } catch (e) {
    reportTest('Test 6: Anonymous shop update -> DENY', false);
  }

  // 7. Anonymous shop delete -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_a').delete());
    reportTest('Test 7: Anonymous shop delete -> DENY', true);
  } catch (e) {
    reportTest('Test 7: Anonymous shop delete -> DENY', false);
  }

  // 8. Customer shop create -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_cust_new').set({ name: 'Customer Shop' }));
    reportTest('Test 8: Customer shop create -> DENY', true);
  } catch (e) {
    reportTest('Test 8: Customer shop create -> DENY', false);
  }

  // 9. Customer shop update -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').update({ name: 'Customer Override' }));
    reportTest('Test 9: Customer shop update -> DENY', true);
  } catch (e) {
    reportTest('Test 9: Customer shop update -> DENY', false);
  }

  // 10. Customer shop delete -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').delete());
    reportTest('Test 10: Customer shop delete -> DENY', true);
  } catch (e) {
    reportTest('Test 10: Customer shop delete -> DENY', false);
  }

  // 11. Shopkeeper own-shop create -> ALLOW where intended
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').set({
      name: 'Rajat Shop Updated',
      id: 'shop_a',
      shopId: 'shop_a',
      isActive: true,
      isClosedOverride: false,
    }));
    reportTest('Test 11: Shopkeeper own-shop create/set -> ALLOW', true);
  } catch (e) {
    reportTest('Test 11: Shopkeeper own-shop create/set -> ALLOW', false);
  }

  // 12. Shopkeeper own-shop update -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').update({
      isClosedOverride: true,
    }));
    reportTest('Test 12: Shopkeeper own-shop update -> ALLOW', true);
  } catch (e) {
    reportTest('Test 12: Shopkeeper own-shop update -> ALLOW', false);
  }

  // 13. Shopkeeper own-shop delete -> DENY (destructive deletion restricted to admin)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').delete());
    reportTest('Test 13: Shopkeeper own-shop delete -> DENY (policy protected)', true);
  } catch (e) {
    reportTest('Test 13: Shopkeeper own-shop delete -> DENY (policy protected)', false);
  }

  // 14. Shopkeeper cross-shop write -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_b').update({
      isClosedOverride: true,
    }));
    reportTest('Test 14: Shopkeeper cross-shop write -> DENY', true);
  } catch (e) {
    reportTest('Test 14: Shopkeeper cross-shop write -> DENY', false);
  }

  // 15. Admin permitted shop operation -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_admin_test').set({
      name: 'Admin Provisioned Shop',
      id: 'shop_admin_test',
      shopId: 'shop_admin_test',
      isActive: true,
    }));
    await assertSucceeds(adminDb.collection('shops').doc('shop_admin_test').delete());
    reportTest('Test 15: Admin permitted shop operation -> ALLOW', true);
  } catch (e) {
    reportTest('Test 15: Admin permitted shop operation -> ALLOW', false);
  }

  console.log('\n--- Phase 3.2: Categories Tier Tests (16 - 22) ---');

  // 16. Anonymous category read -> ALLOW
  try {
    await assertSucceeds(unauthDb.collection('shops').doc('shop_a').collection('categories').doc('cat_a1').get());
    reportTest('Test 16: Anonymous category read -> ALLOW', true);
  } catch (e) {
    reportTest('Test 16: Anonymous category read -> ALLOW', false);
  }

  // 17. Customer category read -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('shops').doc('shop_a').collection('categories').doc('cat_a1').get());
    reportTest('Test 17: Customer category read -> ALLOW', true);
  } catch (e) {
    reportTest('Test 17: Customer category read -> ALLOW', false);
  }

  // 18. Shopkeeper own category write -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_a2').set({
      name: 'Chinese Specialties',
      shopId: 'shop_a',
      isActive: true,
      sortOrder: 2,
    }));
    reportTest('Test 18: Shopkeeper own category write -> ALLOW', true);
  } catch (e) {
    reportTest('Test 18: Shopkeeper own category write -> ALLOW', false);
  }

  // 19. Shopkeeper cross-shop category write -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_b').collection('categories').doc('cat_b2').set({
      name: 'Cross Shop Category',
      shopId: 'shop_b',
    }));
    reportTest('Test 19: Shopkeeper cross-shop category write -> DENY', true);
  } catch (e) {
    reportTest('Test 19: Shopkeeper cross-shop category write -> DENY', false);
  }

  // 20. Customer category write -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').collection('categories').doc('cat_cust').set({
      name: 'Customer Category',
      shopId: 'shop_a',
    }));
    reportTest('Test 20: Customer category write -> DENY', true);
  } catch (e) {
    reportTest('Test 20: Customer category write -> DENY', false);
  }

  // 21. Anonymous category write -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_a').collection('categories').doc('cat_anon').set({
      name: 'Anon Category',
      shopId: 'shop_a',
    }));
    reportTest('Test 21: Anonymous category write -> DENY', true);
  } catch (e) {
    reportTest('Test 21: Anonymous category write -> DENY', false);
  }

  // 22. Admin permitted category operation -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').collection('categories').doc('cat_admin').set({
      name: 'Admin Managed Category',
      shopId: 'shop_a',
      isActive: true,
    }));
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').collection('categories').doc('cat_admin').delete());
    reportTest('Test 22: Admin permitted category operation -> ALLOW', true);
  } catch (e) {
    reportTest('Test 22: Admin permitted category operation -> ALLOW', false);
  }

  console.log('\n--- Phase 3.2: Menu Items Tier Tests (23 - 33) ---');

  // 23. Anonymous menu read -> ALLOW
  try {
    await assertSucceeds(unauthDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').get());
    reportTest('Test 23: Anonymous menu read -> ALLOW', true);
  } catch (e) {
    reportTest('Test 23: Anonymous menu read -> ALLOW', false);
  }

  // 24. Customer menu read -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').get());
    reportTest('Test 24: Customer menu read -> ALLOW', true);
  } catch (e) {
    reportTest('Test 24: Customer menu read -> ALLOW', false);
  }

  // 25. Shopkeeper own menu create -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a2').set({
      name: 'Paneer Fried Momos',
      price: 80,
      shopId: 'shop_a',
      isAvailable: true,
    }));
    reportTest('Test 25: Shopkeeper own menu create -> ALLOW', true);
  } catch (e) {
    reportTest('Test 25: Shopkeeper own menu create -> ALLOW', false);
  }

  // 26. Shopkeeper own menu update -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      price: 70,
      isAvailable: false,
    }));
    reportTest('Test 26: Shopkeeper own menu update -> ALLOW', true);
  } catch (e) {
    reportTest('Test 26: Shopkeeper own menu update -> ALLOW', false);
  }

  // 27. Shopkeeper own menu delete -> ALLOW only where intended
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_to_delete').delete());
    reportTest('Test 27: Shopkeeper own menu delete -> ALLOW', true);
  } catch (e) {
    reportTest('Test 27: Shopkeeper own menu delete -> ALLOW', false);
  }

  // 28. Shopkeeper cross-shop menu create -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_b').collection('menuItems').doc('item_cross_create').set({
      name: 'Cross Shop Item',
      price: 99,
      shopId: 'shop_b',
    }));
    reportTest('Test 28: Shopkeeper cross-shop menu create -> DENY', true);
  } catch (e) {
    reportTest('Test 28: Shopkeeper cross-shop menu create -> DENY', false);
  }

  // 29. Shopkeeper cross-shop menu update -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_b').collection('menuItems').doc('item_b1').update({
      price: 1,
    }));
    reportTest('Test 29: Shopkeeper cross-shop menu update -> DENY', true);
  } catch (e) {
    reportTest('Test 29: Shopkeeper cross-shop menu update -> DENY', false);
  }

  // 30. Shopkeeper cross-shop menu delete -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_b').collection('menuItems').doc('item_b1').delete());
    reportTest('Test 30: Shopkeeper cross-shop menu delete -> DENY', true);
  } catch (e) {
    reportTest('Test 30: Shopkeeper cross-shop menu delete -> DENY', false);
  }

  // 31. Customer menu write -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_cust_hack').set({
      name: 'Free Food',
      price: 0,
      shopId: 'shop_a',
    }));
    reportTest('Test 31: Customer menu write -> DENY', true);
  } catch (e) {
    reportTest('Test 31: Customer menu write -> DENY', false);
  }

  // 32. Anonymous menu write -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_anon_hack').set({
      name: 'Anon Item',
      price: 0,
      shopId: 'shop_a',
    }));
    reportTest('Test 32: Anonymous menu write -> DENY', true);
  } catch (e) {
    reportTest('Test 32: Anonymous menu write -> DENY', false);
  }

  // 33. Admin permitted menu operation -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_admin_special').set({
      name: 'Admin Special Combo',
      price: 250,
      shopId: 'shop_a',
    }));
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_admin_special').delete());
    reportTest('Test 33: Admin permitted menu operation -> ALLOW', true);
  } catch (e) {
    reportTest('Test 33: Admin permitted menu operation -> ALLOW', false);
  }

  console.log('\n--- Phase 3.2: Ownership Mutation Tests (34 - 37) ---');

  // 34. Shopkeeper attempts to change menu shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      shopId: 'shop_b',
    }));
    reportTest('Test 34: Shopkeeper attempts to change menu shopId -> DENY', true);
  } catch (e) {
    reportTest('Test 34: Shopkeeper attempts to change menu shopId -> DENY', false);
  }

  // 35. Shopkeeper attempts to change category shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_a1').update({
      shopId: 'shop_b',
    }));
    reportTest('Test 35: Shopkeeper attempts to change category shopId -> DENY', true);
  } catch (e) {
    reportTest('Test 35: Shopkeeper attempts to change category shopId -> DENY', false);
  }

  // 36. Shopkeeper path shop_A + claimed shop_B -> DENY
  try {
    await assertFails(shopkeeperBDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      price: 999,
    }));
    reportTest('Test 36: Shopkeeper path shop_A + claimed shop_B -> DENY', true);
  } catch (e) {
    reportTest('Test 36: Shopkeeper path shop_A + claimed shop_B -> DENY', false);
  }

  // 37. Invalid/missing shopkeeper shopId -> DENY
  try {
    await assertFails(shopkeeperMissingShopIdDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      price: 999,
    }));
    await assertFails(shopkeeperEmptyShopIdDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      price: 999,
    }));
    reportTest('Test 37: Invalid/missing shopkeeper shopId -> DENY', true);
  } catch (e) {
    reportTest('Test 37: Invalid/missing shopkeeper shopId -> DENY', false);
  }

  // ═════════════════════════════════════════════════════════════════════
  // ADDITIONAL CROSS-SHOP DIRECT ATTACKS & INVARIANTS (38 - 42)
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n--- Phase 3.2: Additional Direct Invariant Attacks (38 - 42) ---');

  // 38. Shopkeeper cross-shop category delete -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_b').collection('categories').doc('cat_b1').delete());
    reportTest('Test 38: Shopkeeper cross-shop category delete -> DENY', true);
  } catch (e) {
    reportTest('Test 38: Shopkeeper cross-shop category delete -> DENY', false);
  }

  // 39. Shopkeeper attempts to mutate shop doc shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      shopId: 'shop_b',
    }));
    reportTest('Test 39: Shopkeeper attempts to mutate shop doc shopId -> DENY', true);
  } catch (e) {
    reportTest('Test 39: Shopkeeper attempts to mutate shop doc shopId -> DENY', false);
  }

  // 40. Shopkeeper attempts to mutate shop doc id -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      id: 'shop_b',
    }));
    reportTest('Test 40: Shopkeeper attempts to mutate shop doc id -> DENY', true);
  } catch (e) {
    reportTest('Test 40: Shopkeeper attempts to mutate shop doc id -> DENY', false);
  }

  // 41. Shopkeeper attempts to create menu item with conflicting payload shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_conflict').set({
      name: 'Conflict Item',
      price: 100,
      shopId: 'shop_b',
    }));
    reportTest('Test 41: Shopkeeper create menu item with conflicting payload shopId -> DENY', true);
  } catch (e) {
    reportTest('Test 41: Shopkeeper create menu item with conflicting payload shopId -> DENY', false);
  }

  // 42. Shopkeeper attempts to create category with conflicting payload shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_conflict').set({
      name: 'Conflict Cat',
      shopId: 'shop_b',
    }));
    reportTest('Test 42: Shopkeeper create category with conflicting payload shopId -> DENY', true);
  } catch (e) {
    reportTest('Test 42: Shopkeeper create category with conflicting payload shopId -> DENY', false);
  }

  // ═════════════════════════════════════════════════════════════════════
  // CHECKPOINT 3.1 REGRESSION BASELINE SUITE
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n--- Regression: Protected Default-Deny Collections ---');

  // Orders Default-Deny
  try {
    await assertFails(unauthDb.collection('orders').doc('order_1').get());
    reportTest('R.1 Anonymous -> protected orders read = DENY', true);
  } catch (e) {
    reportTest('R.1 Anonymous -> protected orders read = DENY', false);
  }
  try {
    await assertFails(unauthDb.collection('orders').doc('order_1').set({
      orderId: 'order_1',
      shopId: 'shop_a',
      customerId: 'anon',
      status: 'placed',
      totalAmount: 100,
    }));
    reportTest('R.2 Anonymous -> protected orders write = DENY', true);
  } catch (e) {
    reportTest('R.2 Anonymous -> protected orders write = DENY', false);
  }
  try {
    await assertFails(unauthDb.collection('orders').doc('order_1').delete());
    reportTest('R.3 Anonymous -> protected orders delete = DENY', true);
  } catch (e) {
    reportTest('R.3 Anonymous -> protected orders delete = DENY', false);
  }

  // ShopStats Default-Deny
  try {
    await assertFails(unauthDb.collection('shopStats').doc('shop_a').get());
    reportTest('R.4 Anonymous -> protected shopStats read = DENY', true);
  } catch (e) {
    reportTest('R.4 Anonymous -> protected shopStats read = DENY', false);
  }
  try {
    await assertFails(unauthDb.collection('shopStats').doc('shop_a').set({ count: 10 }));
    reportTest('R.5 Anonymous -> protected shopStats write = DENY', true);
  } catch (e) {
    reportTest('R.5 Anonymous -> protected shopStats write = DENY', false);
  }

  // DeviceTokens Default-Deny
  try {
    await assertFails(unauthDb.collection('deviceTokens').doc('token_1').get());
    reportTest('R.6 Anonymous -> protected deviceTokens read = DENY', true);
  } catch (e) {
    reportTest('R.6 Anonymous -> protected deviceTokens read = DENY', false);
  }
  try {
    await assertFails(unauthDb.collection('deviceTokens').doc('token_1').delete());
    reportTest('R.7 Anonymous -> protected deviceTokens delete = DENY', true);
  } catch (e) {
    reportTest('R.7 Anonymous -> protected deviceTokens delete = DENY', false);
  }

  // SupportQueries Baseline
  try {
    await assertFails(unauthDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.8 Anonymous -> protected supportQueries read = DENY', true);
  } catch (e) {
    reportTest('R.8 Anonymous -> protected supportQueries read = DENY', false);
  }

  // App Config Baseline
  try {
    await assertSucceeds(unauthDb.collection('config').doc('app_config').get());
    reportTest('R.9 Anonymous can read /config/app_config = ALLOW', true);
  } catch (e) {
    reportTest('R.9 Anonymous can read /config/app_config = ALLOW', false);
  }
  try {
    await assertFails(unauthDb.collection('config').doc('app_config').set({ maintenance: true }));
    reportTest('R.10 Anonymous cannot write /config/app_config = DENY', true);
  } catch (e) {
    reportTest('R.10 Anonymous cannot write /config/app_config = DENY', false);
  }

  console.log('\n--- Regression: Customer Boundary Tests ---');
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.11 Customer -> privileged supportQueries read = DENY', true);
  } catch (e) {
    reportTest('R.11 Customer -> privileged supportQueries read = DENY', false);
  }
  try {
    await assertFails(customerDb.collection('shopStats').doc('shop_a').get());
    reportTest('R.12 Customer -> privileged shopStats read = DENY', true);
  } catch (e) {
    reportTest('R.12 Customer -> privileged shopStats read = DENY', false);
  }
  try {
    await assertFails(customerDb.collection('shopStats').doc('shop_a').set({ totalOrders: 0 }));
    reportTest('R.13 Customer -> privileged shopStats write = DENY', true);
  } catch (e) {
    reportTest('R.13 Customer -> privileged shopStats write = DENY', false);
  }
  try {
    await assertFails(customerDb.collection('auditLogs').doc('log_1').set({ event: 'hacked' }));
    reportTest('R.14 Customer -> arbitrary collection write = DENY', true);
  } catch (e) {
    reportTest('R.14 Customer -> arbitrary collection write = DENY', false);
  }
  try {
    await assertFails(customerDb.collection('users').doc('user_other').set({ role: 'admin' }));
    reportTest('R.15 Customer -> arbitrary users collection write = DENY', true);
  } catch (e) {
    reportTest('R.15 Customer -> arbitrary users collection write = DENY', false);
  }

  console.log('\n--- Regression: Shopkeeper Boundary Tests ---');
  try {
    await assertFails(shopkeeperADb.collection('supportQueries').doc('query_1').get());
    reportTest('R.16 Shopkeeper -> privileged supportQueries read = DENY', true);
  } catch (e) {
    reportTest('R.16 Shopkeeper -> privileged supportQueries read = DENY', false);
  }
  try {
    await assertFails(shopkeeperADb.collection('auditLogs').doc('log_1').set({ event: 'reset' }));
    reportTest('R.17 Shopkeeper -> arbitrary privileged collection write = DENY', true);
  } catch (e) {
    reportTest('R.17 Shopkeeper -> arbitrary privileged collection write = DENY', false);
  }
  try {
    await assertFails(shopkeeperADb.collection('adminSettings').doc('system').get());
    reportTest('R.18 Shopkeeper -> arbitrary collection access = DENY', true);
  } catch (e) {
    reportTest('R.18 Shopkeeper -> arbitrary collection access = DENY', false);
  }

  console.log('\n--- Regression: Admin Boundary & Strict Claim Tests ---');
  try {
    await assertSucceeds(adminDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.19 Valid admin claim {role: "admin"} -> allowed = ALLOW', true);
  } catch (e) {
    reportTest('R.19 Valid admin claim {role: "admin"} -> allowed = ALLOW', false);
  }
  try {
    await assertFails(customerWithAdminPhoneDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.20 Customer with admin-looking phone data -> DENY', true);
  } catch (e) {
    reportTest('R.20 Customer with admin-looking phone data -> DENY', false);
  }
  try {
    await assertFails(shopkeeperWithAdminPhoneDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.21 Shopkeeper with admin-looking phone data -> DENY', true);
  } catch (e) {
    reportTest('R.21 Shopkeeper with admin-looking phone data -> DENY', false);
  }
  try {
    await assertFails(userWithAdminFlagDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.22 Authenticated user with admin: true but role != admin -> DENY', true);
  } catch (e) {
    reportTest('R.22 Authenticated user with admin: true but role != admin -> DENY', false);
  }
  try {
    await assertFails(userWithAdminPhoneOnlyDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.23 User with former admin phone but missing role claim -> DENY', true);
  } catch (e) {
    reportTest('R.23 User with former admin phone but missing role claim -> DENY', false);
  }
  try {
    await assertFails(userWithMissingRoleDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.24 Authenticated user with missing role claim -> DENY', true);
  } catch (e) {
    reportTest('R.24 Authenticated user with missing role claim -> DENY', false);
  }
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_1').get());
    reportTest('R.25 role: customer -> denied for admin-only resource = DENY', true);
  } catch (e) {
    reportTest('R.25 role: customer -> denied for admin-only resource = DENY', false);
  }
  try {
    await assertFails(shopkeeperADb.collection('supportQueries').doc('query_1').get());
    reportTest('R.26 role: shopkeeper -> denied for admin-only resource = DENY', true);
  } catch (e) {
    reportTest('R.26 role: shopkeeper -> denied for admin-only resource = DENY', false);
  }
  try {
    await assertFails(adminDb.collection('unconfigured_collection').doc('doc_1').get());
    reportTest('R.27 Admin does NOT receive blanket access (deny-by-default preserved) = DENY', true);
  } catch (e) {
    reportTest('R.27 Admin does NOT receive blanket access (deny-by-default preserved) = DENY', false);
  }
  try {
    await assertFails(adminDb.collection('unconfigured_collection').doc('doc_1').set({ val: 1 }));
    reportTest('R.28 Admin write to unconfigured collection = DENY', true);
  } catch (e) {
    reportTest('R.28 Admin write to unconfigured collection = DENY', false);
  }

  console.log('\n--- Regression: Direct Client API Bypass Negative Tests ---');
  try {
    await assertFails(attackerDb.collection('orders').doc('victim_order_123').get());
    reportTest('R.29 Authenticated attacker direct API read to orders = DENY', true);
  } catch (e) {
    reportTest('R.29 Authenticated attacker direct API read to orders = DENY', false);
  }
  try {
    await assertFails(attackerDb.collection('shopStats').doc('shop_a').set({ revenue: 0 }));
    reportTest('R.30 Authenticated attacker direct API write to shopStats = DENY', true);
  } catch (e) {
    reportTest('R.30 Authenticated attacker direct API write to shopStats = DENY', false);
  }

  console.log('\n--- Regression: Universal Fallthrough Denial Tests ---');
  try {
    await assertFails(unauthDb.collection('random_secret_vault').doc('key').get());
    reportTest('R.31 Anonymous read on unknown collection = DENY', true);
  } catch (e) {
    reportTest('R.31 Anonymous read on unknown collection = DENY', false);
  }
  try {
    await assertFails(unauthDb.collection('random_secret_vault').doc('key').set({ secret: 'stolen' }));
    reportTest('R.32 Anonymous write on unknown collection = DENY', true);
  } catch (e) {
    reportTest('R.32 Anonymous write on unknown collection = DENY', false);
  }
  try {
    await assertFails(customerDb.collection('internal_metrics').doc('m1').set({ val: 99 }));
    reportTest('R.33 Customer write on unknown collection = DENY', true);
  } catch (e) {
    reportTest('R.33 Customer write on unknown collection = DENY', false);
  }
  try {
    await assertFails(shopkeeperADb.collection('internal_metrics').doc('m1').set({ val: 99 }));
    reportTest('R.34 Shopkeeper write on unknown collection = DENY', true);
  } catch (e) {
    reportTest('R.34 Shopkeeper write on unknown collection = DENY', false);
  }

  console.log('\n=================================================================');
  console.log(`  RESULTS: ${passCount} / ${totalTests} TESTS PASSED  `);
  console.log('=================================================================\n');

  await testEnv.cleanup();

  if (passCount !== totalTests) {
    console.error(`FAILED: ${totalTests - passCount} tests failed!`);
    process.exit(1);
  }
}

setup()
  .then(runRulesSecuritySuite)
  .catch((err) => {
    console.error('Fatal test error:', err);
    process.exit(1);
  });
