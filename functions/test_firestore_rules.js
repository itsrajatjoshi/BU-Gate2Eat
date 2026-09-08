/**
 * YummBU / BU Gate2Eat — Firestore Security Rules Unit Tests
 * 
 * Checkpoint 3.2 Remediation: Shops / Categories / Menu Rules & Tenant Isolation
 * 
 * Tests against live Firebase Firestore Emulator using @firebase/rules-unit-testing.
 * Proves that database-level authorization enforces:
 *  - Public catalog browsing where intended
 *  - Shop creation strictly Admin-only
 *  - Category/Menu creation strictly requires valid matching shopId (mandatory tenant field)
 *  - Category/Menu update strictly requires both existing and updated docs to possess valid matching shopId
 *  - Existing malformed/missing-tenant documents cannot be updated as valid tenant documents
 *  - Strict tenant boundary: shopkeepers write ONLY to their assigned shopId
 *  - Cross-tenant attack rejection (Shopkeeper A -> Shopkeeper B denied)
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
const { deleteField } = require('@firebase/firestore');

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
    // Seed malformed category (missing shopId field)
    await adminFs.collection('shops').doc('shop_a').collection('categories').doc('cat_malformed_no_shopid').set({
      name: 'Malformed Category',
      isActive: true,
      sortOrder: 9,
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
    // Seed malformed menu item (missing shopId field)
    await adminFs.collection('shops').doc('shop_a').collection('menuItems').doc('item_malformed_no_shopid').set({
      name: 'Malformed Legacy Item',
      price: 99,
      isAvailable: true,
    });

    // Seed test orders for Phase 3.3
    const orderDataA = {
      orderId: 'order_cust_a_shop_a',
      customerId: 'customer_a',
      customerName: 'Customer A',
      customerPhone: '+919876543210',
      shopId: 'shop_a',
      shopName: 'Shop A',
      status: 'placed',
      totalAmount: 250,
      grandTotal: 250,
      subtotal: 250,
      deliveryCharges: 0,
      items: [{ itemId: 'item_1', name: 'Burger', price: 250, quantity: 1 }],
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    await adminFs.collection('orders').doc('order_cust_a_shop_a').set(orderDataA);

    const orderDataB = {
      orderId: 'order_cust_b_shop_b',
      customerId: 'customer_b',
      customerName: 'Customer B',
      customerPhone: '+919876543211',
      shopId: 'shop_b',
      shopName: 'Shop B',
      status: 'placed',
      totalAmount: 180,
      grandTotal: 180,
      subtotal: 180,
      deliveryCharges: 0,
      items: [{ itemId: 'item_2', name: 'Pizza', price: 180, quantity: 1 }],
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    await adminFs.collection('orders').doc('order_cust_b_shop_b').set(orderDataB);

    await adminFs.collection('orders').doc('order_cust_a_accepted').set({
      ...orderDataA,
      orderId: 'order_cust_a_accepted',
      status: 'accepted',
      acceptedAt: new Date(),
    });

    await adminFs.collection('orders').doc('order_cust_a_for_cancel').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_cancel',
    });

    await adminFs.collection('orders').doc('order_cust_a_for_sk_update').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_sk_update',
    });

    await adminFs.collection('orders').doc('order_cust_a_for_sk_deliver').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_sk_deliver',
      status: 'accepted',
      acceptedAt: new Date(),
    });

    await adminFs.collection('orders').doc('order_cust_a_for_admin_update').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_admin_update',
    });

    await adminFs.collection('orders').doc('order_cust_a_for_admin_immutability').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_admin_immutability',
    });

    await adminFs.collection('orders').doc('order_delete_target').set({
      ...orderDataA,
      orderId: 'order_delete_target',
    });

    // Dedicated seed docs for Phase 3.3 Lifecycle Remediation Tests
    await adminFs.collection('orders').doc('order_cust_a_for_sk_status_rem').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_sk_status_rem',
    });

    await adminFs.collection('orders').doc('order_cust_a_for_sk_reject_rem').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_sk_reject_rem',
    });

    await adminFs.collection('orders').doc('order_cust_a_for_sk_delivery_rem').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_sk_delivery_rem',
      status: 'accepted',
      acceptedAt: new Date(),
    });

    await adminFs.collection('orders').doc('order_cust_a_for_cancel_rem').set({
      ...orderDataA,
      orderId: 'order_cust_a_for_cancel_rem',
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

  // 11. Shopkeeper own-shop create -> DENY (Admin-only creation policy)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_uncreated_a').set({
      name: 'Rajat Shop New',
      id: 'shop_uncreated_a',
      shopId: 'shop_uncreated_a',
      isActive: true,
    }));
    reportTest('Test 11: Shopkeeper own-shop create -> DENY (Admin-only creation policy)', true);
  } catch (e) {
    reportTest('Test 11: Shopkeeper own-shop create -> DENY (Admin-only creation policy)', false);
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
  // PHASE 3.2 REMEDIATION: STRICT TENANT FIELD INVARIANTS (Rem.1 - 19)
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n--- Phase 3.2 Remediation: Admin-Only Shop Creation (Rem.1 - 5) ---');

  // Rem.1 Admin can create shop with valid path/identity -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_admin_remediation').set({
      name: 'Admin Rem Shop',
      id: 'shop_admin_remediation',
      shopId: 'shop_admin_remediation',
      isActive: true,
    }));
    await assertSucceeds(adminDb.collection('shops').doc('shop_admin_remediation').delete());
    reportTest('Rem.1: Admin can create shop with valid path/identity -> ALLOW', true);
  } catch (e) {
    reportTest('Rem.1: Admin can create shop with valid path/identity -> ALLOW', false);
  }

  // Rem.2 Shopkeeper attempting to create assigned shop -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_uncreated_a_rem').set({
      name: 'Shopkeeper Created Shop',
      id: 'shop_uncreated_a_rem',
      shopId: 'shop_uncreated_a_rem',
      isActive: true,
    }));
    reportTest('Rem.2: Shopkeeper attempting to create assigned shop -> DENY', true);
  } catch (e) {
    reportTest('Rem.2: Shopkeeper attempting to create assigned shop -> DENY', false);
  }

  // Rem.3 Shopkeeper attempting to create another shop -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_uncreated_b_rem').set({
      name: 'Shopkeeper Cross Shop',
      id: 'shop_uncreated_b_rem',
      shopId: 'shop_uncreated_b_rem',
      isActive: true,
    }));
    reportTest('Rem.3: Shopkeeper attempting to create another shop -> DENY', true);
  } catch (e) {
    reportTest('Rem.3: Shopkeeper attempting to create another shop -> DENY', false);
  }

  // Rem.4 Customer shop creation -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_cust_rem').set({
      name: 'Customer Shop',
      id: 'shop_cust_rem',
    }));
    reportTest('Rem.4: Customer shop creation -> DENY', true);
  } catch (e) {
    reportTest('Rem.4: Customer shop creation -> DENY', false);
  }

  // Rem.5 Anonymous shop creation -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_anon_rem').set({
      name: 'Anon Shop',
      id: 'shop_anon_rem',
    }));
    reportTest('Rem.5: Anonymous shop creation -> DENY', true);
  } catch (e) {
    reportTest('Rem.5: Anonymous shop creation -> DENY', false);
  }

  console.log('\n--- Phase 3.2 Remediation: Category Creation Invariants (Rem.6 - 10) ---');

  // Rem.6 Shopkeeper creates category with matching shopId -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_rem_valid').set({
      name: 'Valid Category',
      shopId: 'shop_a',
      isActive: true,
    }));
    reportTest('Rem.6: Shopkeeper creates category with matching shopId -> ALLOW', true);
  } catch (e) {
    reportTest('Rem.6: Shopkeeper creates category with matching shopId -> ALLOW', false);
  }

  // Rem.7 Shopkeeper creates category with missing shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_rem_missing').set({
      name: 'Missing ShopId Category',
      isActive: true,
    }));
    reportTest('Rem.7: Shopkeeper creates category with missing shopId -> DENY', true);
  } catch (e) {
    reportTest('Rem.7: Shopkeeper creates category with missing shopId -> DENY', false);
  }

  // Rem.8 Shopkeeper creates category with foreign shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_rem_foreign').set({
      name: 'Foreign ShopId Category',
      shopId: 'shop_b',
    }));
    reportTest('Rem.8: Shopkeeper creates category with foreign shopId -> DENY', true);
  } catch (e) {
    reportTest('Rem.8: Shopkeeper creates category with foreign shopId -> DENY', false);
  }

  // Rem.9 Admin creates category with matching path shopId -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').collection('categories').doc('cat_admin_rem_valid').set({
      name: 'Admin Category',
      shopId: 'shop_a',
      isActive: true,
    }));
    reportTest('Rem.9: Admin creates category with matching path shopId -> ALLOW', true);
  } catch (e) {
    reportTest('Rem.9: Admin creates category with matching path shopId -> ALLOW', false);
  }

  // Rem.10 Admin creates category with foreign/mismatched shopId -> DENY
  try {
    await assertFails(adminDb.collection('shops').doc('shop_a').collection('categories').doc('cat_admin_rem_mismatch').set({
      name: 'Mismatched Admin Category',
      shopId: 'shop_b',
    }));
    reportTest('Rem.10: Admin creates category with foreign/mismatched shopId -> DENY', true);
  } catch (e) {
    reportTest('Rem.10: Admin creates category with foreign/mismatched shopId -> DENY', false);
  }

  console.log('\n--- Phase 3.2 Remediation: Menu Creation Invariants (Rem.11 - 15) ---');

  // Rem.11 Shopkeeper creates menu item with matching shopId -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_rem_valid').set({
      name: 'Valid Item',
      price: 100,
      shopId: 'shop_a',
      isAvailable: true,
    }));
    reportTest('Rem.11: Shopkeeper creates menu item with matching shopId -> ALLOW', true);
  } catch (e) {
    reportTest('Rem.11: Shopkeeper creates menu item with matching shopId -> ALLOW', false);
  }

  // Rem.12 Shopkeeper creates menu item with missing shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_rem_missing').set({
      name: 'Missing ShopId Item',
      price: 100,
      isAvailable: true,
    }));
    reportTest('Rem.12: Shopkeeper creates menu item with missing shopId -> DENY', true);
  } catch (e) {
    reportTest('Rem.12: Shopkeeper creates menu item with missing shopId -> DENY', false);
  }

  // Rem.13 Shopkeeper creates menu item with foreign shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_rem_foreign').set({
      name: 'Foreign ShopId Item',
      price: 100,
      shopId: 'shop_b',
      isAvailable: true,
    }));
    reportTest('Rem.13: Shopkeeper creates menu item with foreign shopId -> DENY', true);
  } catch (e) {
    reportTest('Rem.13: Shopkeeper creates menu item with foreign shopId -> DENY', false);
  }

  // Rem.14 Admin creates menu item with matching path shopId -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_admin_rem_valid').set({
      name: 'Admin Menu Item',
      price: 120,
      shopId: 'shop_a',
      isAvailable: true,
    }));
    reportTest('Rem.14: Admin creates menu item with matching path shopId -> ALLOW', true);
  } catch (e) {
    reportTest('Rem.14: Admin creates menu item with matching path shopId -> ALLOW', false);
  }

  // Rem.15 Admin creates menu item with mismatched shopId -> DENY
  try {
    await assertFails(adminDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_admin_rem_mismatch').set({
      name: 'Admin Mismatched Item',
      price: 120,
      shopId: 'shop_b',
      isAvailable: true,
    }));
    reportTest('Rem.15: Admin creates menu item with mismatched shopId -> DENY', true);
  } catch (e) {
    reportTest('Rem.15: Admin creates menu item with mismatched shopId -> DENY', false);
  }

  console.log('\n--- Phase 3.2 Remediation: Update Integrity Invariants (Rem.16 - 19) ---');

  // Rem.16 Valid shopkeeper update preserves matching shopId -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      price: 75,
      shopId: 'shop_a',
    }));
    reportTest('Rem.16: Valid shopkeeper update preserves matching shopId -> ALLOW', true);
  } catch (e) {
    reportTest('Rem.16: Valid shopkeeper update preserves matching shopId -> ALLOW', false);
  }

  // Rem.17 Shopkeeper removes shopId during update -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      shopId: deleteField(),
    }));
    reportTest('Rem.17: Shopkeeper removes shopId during update -> DENY', true);
  } catch (e) {
    reportTest('Rem.17: Shopkeeper removes shopId during update -> DENY', false);
  }

  // Rem.18 Shopkeeper changes shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      shopId: 'shop_b',
    }));
    reportTest('Rem.18: Shopkeeper changes shopId -> DENY', true);
  } catch (e) {
    reportTest('Rem.18: Shopkeeper changes shopId -> DENY', false);
  }

  // Rem.19 Existing malformed/missing-tenant resource cannot be updated as if valid tenant resource -> DENY
  try {
    // Both for category and menu item lacking stored shopId in resource.data
    const p1 = assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_malformed_no_shopid').update({
      name: 'Attempted Patch',
      shopId: 'shop_a',
    }));
    const p2 = assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_malformed_no_shopid').update({
      price: 150,
      shopId: 'shop_a',
    }));
    await Promise.all([p1, p2]);
    reportTest('Rem.19: Existing malformed/missing-tenant resource cannot be updated -> DENY', true);
  } catch (e) {
    reportTest('Rem.19: Existing malformed/missing-tenant resource cannot be updated -> DENY', false);
  }

  // ═════════════════════════════════════════════════════════════════════
  // CHECKPOINT 3.1 REGRESSION BASELINE SUITE (R.1 - 34)
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

  // ═════════════════════════════════════════════════════════════════════
  // CHECKPOINT 3.3 ORDERS SECURITY SUITE (O.1 - O.35)
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n--- Phase 3.3: Anonymous Order Access Tests (O.1 - O.4) ---');

  // O.1 Anonymous order read -> DENY
  try {
    await assertFails(unauthDb.collection('orders').doc('order_cust_a_shop_a').get());
    reportTest('O.1 Anonymous order read -> DENY', true);
  } catch (e) {
    reportTest('O.1 Anonymous order read -> DENY', false);
  }

  // O.2 Anonymous order create -> DENY
  try {
    await assertFails(unauthDb.collection('orders').doc('order_anon_create').set({
      orderId: 'order_anon_create',
      customerId: 'anon',
      shopId: 'shop_a',
      status: 'placed',
      totalAmount: 100,
    }));
    reportTest('O.2 Anonymous order create -> DENY', true);
  } catch (e) {
    reportTest('O.2 Anonymous order create -> DENY', false);
  }

  // O.3 Anonymous order update -> DENY
  try {
    await assertFails(unauthDb.collection('orders').doc('order_cust_a_shop_a').update({
      status: 'cancelled',
    }));
    reportTest('O.3 Anonymous order update -> DENY', true);
  } catch (e) {
    reportTest('O.3 Anonymous order update -> DENY', false);
  }

  // O.4 Anonymous order delete -> DENY
  try {
    await assertFails(unauthDb.collection('orders').doc('order_delete_target').delete());
    reportTest('O.4 Anonymous order delete -> DENY', true);
  } catch (e) {
    reportTest('O.4 Anonymous order delete -> DENY', false);
  }

  console.log('\n--- Phase 3.3: Customer Order Access Tests (O.5 - O.12) ---');

  // O.5 Customer reads own order -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('orders').doc('order_cust_a_shop_a').get());
    reportTest('O.5 Customer reads own order -> ALLOW', true);
  } catch (e) {
    reportTest('O.5 Customer reads own order -> ALLOW', false);
  }

  // O.6 Customer reads another customer order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_b_shop_b').get());
    reportTest('O.6 Customer reads another customer order -> DENY', true);
  } catch (e) {
    reportTest('O.6 Customer reads another customer order -> DENY', false);
  }

  // O.7 Customer creates own order -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('orders').doc('order_new_cust_a').set({
      orderId: 'order_new_cust_a',
      customerId: 'customer_a',
      shopId: 'shop_a',
      status: 'placed',
      totalAmount: 200,
      items: [{ itemId: 'item_1', name: 'Burger', price: 200, quantity: 1 }],
      createdAt: new Date(),
    }));
    reportTest('O.7 Customer creates own order -> ALLOW', true);
  } catch (e) {
    reportTest('O.7 Customer creates own order -> ALLOW', false);
  }

  // O.8 Customer creates order with foreign customerId -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_forged_cust').set({
      orderId: 'order_forged_cust',
      customerId: 'customer_b',
      shopId: 'shop_a',
      status: 'placed',
      totalAmount: 200,
      items: [{ itemId: 'item_1', name: 'Burger', price: 200, quantity: 1 }],
    }));
    reportTest('O.8 Customer creates order with foreign customerId -> DENY', true);
  } catch (e) {
    reportTest('O.8 Customer creates order with foreign customerId -> DENY', false);
  }

  // O.9 Customer changes order customerId -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      customerId: 'customer_b',
    }));
    reportTest('O.9 Customer changes order customerId -> DENY', true);
  } catch (e) {
    reportTest('O.9 Customer changes order customerId -> DENY', false);
  }

  // O.10 Customer changes order shopId -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      shopId: 'shop_b',
    }));
    reportTest('O.10 Customer changes order shopId -> DENY', true);
  } catch (e) {
    reportTest('O.10 Customer changes order shopId -> DENY', false);
  }

  // O.11 Customer updates protected status/financial fields -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      status: 'accepted',
    }));
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      totalAmount: 50,
    }));
    await assertFails(customerDb.collection('orders').doc('order_cust_a_accepted').update({
      status: 'cancelled',
    }));
    reportTest('O.11 Customer updates protected status/financial fields -> DENY', true);
  } catch (e) {
    reportTest('O.11 Customer updates protected status/financial fields -> DENY', false);
  }

  // O.12 Customer updates another customer order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_b_shop_b').update({
      status: 'cancelled',
    }));
    reportTest('O.12 Customer updates another customer order -> DENY', true);
  } catch (e) {
    reportTest('O.12 Customer updates another customer order -> DENY', false);
  }

  console.log('\n--- Phase 3.3: Shopkeeper Order Access Tests (O.13 - O.20) ---');

  // O.13 Shopkeeper reads own-shop order -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').get());
    reportTest('O.13 Shopkeeper reads own-shop order -> ALLOW', true);
  } catch (e) {
    reportTest('O.13 Shopkeeper reads own-shop order -> ALLOW', false);
  }

  // O.14 Shopkeeper reads another-shop order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_b_shop_b').get());
    reportTest('O.14 Shopkeeper reads another-shop order -> DENY', true);
  } catch (e) {
    reportTest('O.14 Shopkeeper reads another-shop order -> DENY', false);
  }

  // O.15 Shopkeeper updates own-shop order -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_cust_a_for_sk_update').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('O.15 Shopkeeper updates own-shop order -> ALLOW', true);
  } catch (e) {
    reportTest('O.15 Shopkeeper updates own-shop order -> ALLOW', false);
  }

  // O.16 Shopkeeper updates another-shop order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_b_shop_b').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('O.16 Shopkeeper updates another-shop order -> DENY', true);
  } catch (e) {
    reportTest('O.16 Shopkeeper updates another-shop order -> DENY', false);
  }

  // O.17 Shopkeeper changes order shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      shopId: 'shop_b',
    }));
    reportTest('O.17 Shopkeeper changes order shopId -> DENY', true);
  } catch (e) {
    reportTest('O.17 Shopkeeper changes order shopId -> DENY', false);
  }

  // O.18 Shopkeeper changes customerId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      customerId: 'attacker_uid',
    }));
    reportTest('O.18 Shopkeeper changes customerId -> DENY', true);
  } catch (e) {
    reportTest('O.18 Shopkeeper changes customerId -> DENY', false);
  }

  // O.19 Shopkeeper changes protected financial ownership fields -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      totalAmount: 9999,
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      items: [{ itemId: 'hacked', name: 'Free', price: 0, quantity: 1 }],
    }));
    reportTest('O.19 Shopkeeper changes protected financial ownership fields -> DENY', true);
  } catch (e) {
    reportTest('O.19 Shopkeeper changes protected financial ownership fields -> DENY', false);
  }

  // O.20 Shopkeeper creates unauthorized order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_sk_bootstrap').set({
      orderId: 'order_sk_bootstrap',
      customerId: 'customer_a',
      shopId: 'shop_a',
      status: 'placed',
      totalAmount: 100,
    }));
    reportTest('O.20 Shopkeeper creates unauthorized order -> DENY', true);
  } catch (e) {
    reportTest('O.20 Shopkeeper creates unauthorized order -> DENY', false);
  }

  console.log('\n--- Phase 3.3: Admin Order Access Tests (O.21 - O.24) ---');

  // O.21 Admin reads order -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('orders').doc('order_cust_a_shop_a').get());
    reportTest('O.21 Admin reads order -> ALLOW', true);
  } catch (e) {
    reportTest('O.21 Admin reads order -> ALLOW', false);
  }

  // O.22 Admin allowed order operation -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('orders').doc('order_cust_a_for_admin_update').update({
      adminNote: 'Verified and approved by administrator',
      updatedAt: new Date(),
    }));
    reportTest('O.22 Admin allowed order operation -> ALLOW', true);
  } catch (e) {
    reportTest('O.22 Admin allowed order operation -> ALLOW', false);
  }

  // O.23 Admin cannot bypass ownership immutability accidentally -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_cust_a_for_admin_immutability').update({
      customerId: 'reassigned_customer',
    }));
    await assertFails(adminDb.collection('orders').doc('order_cust_a_for_admin_immutability').update({
      shopId: 'reassigned_shop',
    }));
    reportTest('O.23 Admin cannot bypass ownership immutability accidentally -> DENY', true);
  } catch (e) {
    reportTest('O.23 Admin cannot bypass ownership immutability accidentally -> DENY', false);
  }

  // O.24 Non-admin cannot perform admin-only order operation -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      adminNote: 'Customer attempted write to adminNote',
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      adminNote: 'Shopkeeper attempted write to adminNote',
    }));
    reportTest('O.24 Non-admin cannot perform admin-only order operation -> DENY', true);
  } catch (e) {
    reportTest('O.24 Non-admin cannot perform admin-only order operation -> DENY', false);
  }

  console.log('\n--- Phase 3.3: Query Isolation & Direct Read Tests (O.25 - O.28) ---');

  // O.25 Customer order query returns/permits only own tenant
  try {
    await assertSucceeds(customerDb.collection('orders').where('customerId', '==', 'customer_a').get());
    await assertFails(customerDb.collection('orders').where('customerId', '==', 'customer_b').get());
    await assertFails(customerDb.collection('orders').get());
    reportTest('O.25 Customer order query returns/permits only own tenant -> ALLOW own, DENY foreign/unfiltered', true);
  } catch (e) {
    reportTest('O.25 Customer order query returns/permits only own tenant -> ALLOW own, DENY foreign/unfiltered', false);
  }

  // O.26 Shopkeeper order query returns/permits only own shop
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').where('shopId', '==', 'shop_a').get());
    await assertFails(shopkeeperADb.collection('orders').where('shopId', '==', 'shop_b').get());
    await assertFails(shopkeeperADb.collection('orders').get());
    reportTest('O.26 Shopkeeper order query returns/permits only own shop -> ALLOW own, DENY foreign/unfiltered', true);
  } catch (e) {
    reportTest('O.26 Shopkeeper order query returns/permits only own shop -> ALLOW own, DENY foreign/unfiltered', false);
  }

  // O.27 Cross-customer direct document read -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_b_shop_b').get());
    reportTest('O.27 Cross-customer direct document read -> DENY', true);
  } catch (e) {
    reportTest('O.27 Cross-customer direct document read -> DENY', false);
  }

  // O.28 Cross-shop direct document read -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_b_shop_b').get());
    reportTest('O.28 Cross-shop direct document read -> DENY', true);
  } catch (e) {
    reportTest('O.28 Cross-shop direct document read -> DENY', false);
  }

  console.log('\n--- Phase 3.3: Order Deletion Policy Tests (O.29 - O.30) ---');

  // O.29 Unauthorized order deletion -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_delete_target').delete());
    await assertFails(shopkeeperADb.collection('orders').doc('order_delete_target').delete());
    await assertFails(unauthDb.collection('orders').doc('order_delete_target').delete());
    reportTest('O.29 Unauthorized order deletion -> DENY', true);
  } catch (e) {
    reportTest('O.29 Unauthorized order deletion -> DENY', false);
  }

  // O.30 Chosen admin/deletion policy is explicitly tested -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_delete_target').delete());
    reportTest('O.30 Chosen admin/deletion policy is explicitly tested (Direct deletion DENIED) -> DENY', true);
  } catch (e) {
    reportTest('O.30 Chosen admin/deletion policy is explicitly tested (Direct deletion DENIED) -> DENY', false);
  }

  console.log('\n--- Phase 3.3: Additional Edge Invariants Tests (O.31 - O.35) ---');

  // O.31 Customer cancels own placed order -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('orders').doc('order_cust_a_for_cancel').update({
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('O.31 Customer cancels own placed order -> ALLOW', true);
  } catch (e) {
    reportTest('O.31 Customer cancels own placed order -> ALLOW', false);
  }

  // O.32 Customer creates order without shopId -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_no_shop').set({
      orderId: 'order_no_shop',
      customerId: 'customer_a',
      status: 'placed',
      totalAmount: 100,
    }));
    reportTest('O.32 Customer creates order without shopId -> DENY', true);
  } catch (e) {
    reportTest('O.32 Customer creates order without shopId -> DENY', false);
  }

  // O.33 Customer creates order with empty shopId -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_empty_shop').set({
      orderId: 'order_empty_shop',
      customerId: 'customer_a',
      shopId: '',
      status: 'placed',
      totalAmount: 100,
    }));
    reportTest('O.33 Customer creates order with empty shopId -> DENY', true);
  } catch (e) {
    reportTest('O.33 Customer creates order with empty shopId -> DENY', false);
  }

  // O.34 Customer creates order with initial status != placed -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_bad_status').set({
      orderId: 'order_bad_status',
      customerId: 'customer_a',
      shopId: 'shop_a',
      status: 'delivered',
      totalAmount: 100,
    }));
    reportTest('O.34 Customer creates order with initial status != placed -> DENY', true);
  } catch (e) {
    reportTest('O.34 Customer creates order with initial status != placed -> DENY', false);
  }

  // O.35 Shopkeeper marks order delivered with delivery person details -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_cust_a_for_sk_deliver').update({
      status: 'delivered',
      deliveryPersonId: 'delivery_boy_1',
      deliveryPersonName: 'Ramesh',
      updatedAt: new Date(),
    }));
    reportTest('O.35 Shopkeeper marks order delivered with delivery person details -> ALLOW', true);
  } catch (e) {
    reportTest('O.35 Shopkeeper marks order delivered with delivery person details -> ALLOW', false);
  }

  // ═════════════════════════════════════════════════════════════════════
  // PHASE 3.3 REMEDIATION: LIFECYCLE FIELDS PROTECTION SUITE (Rem33.1 - 12)
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n--- Phase 3.3 Remediation: Lifecycle Fields Protection Suite (Rem33.1 - Rem33.12) ---');

  // Rem33.1 Shopkeeper cannot arbitrarily change acceptedAt -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptedAt: new Date(),
    }));
    reportTest('Rem33.1 Shopkeeper cannot arbitrarily change acceptedAt -> DENY', true);
  } catch (e) {
    reportTest('Rem33.1 Shopkeeper cannot arbitrarily change acceptedAt -> DENY', false);
  }

  // Rem33.2 Shopkeeper cannot arbitrarily change rejectedAt -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      rejectedAt: new Date(),
    }));
    reportTest('Rem33.2 Shopkeeper cannot arbitrarily change rejectedAt -> DENY', true);
  } catch (e) {
    reportTest('Rem33.2 Shopkeeper cannot arbitrarily change rejectedAt -> DENY', false);
  }

  // Rem33.3 Shopkeeper cannot arbitrarily change deliveredAt -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      deliveredAt: new Date(),
    }));
    reportTest('Rem33.3 Shopkeeper cannot arbitrarily change deliveredAt -> DENY', true);
  } catch (e) {
    reportTest('Rem33.3 Shopkeeper cannot arbitrarily change deliveredAt -> DENY', false);
  }

  // Rem33.4 Shopkeeper cannot arbitrarily extend rejectDeadline -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      rejectDeadline: new Date(Date.now() + 86400000),
    }));
    reportTest('Rem33.4 Shopkeeper cannot arbitrarily extend rejectDeadline -> DENY', true);
  } catch (e) {
    reportTest('Rem33.4 Shopkeeper cannot arbitrarily extend rejectDeadline -> DENY', false);
  }

  // Rem33.5 Shopkeeper cannot arbitrarily extend deliveryDeadline -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      deliveryDeadline: new Date(Date.now() + 86400000),
    }));
    reportTest('Rem33.5 Shopkeeper cannot arbitrarily extend deliveryDeadline -> DENY', true);
  } catch (e) {
    reportTest('Rem33.5 Shopkeeper cannot arbitrarily extend deliveryDeadline -> DENY', false);
  }

  // Rem33.6 Shopkeeper cannot modify acceptDeadline -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptDeadline: new Date(Date.now() + 86400000),
    }));
    reportTest('Rem33.6 Shopkeeper cannot modify acceptDeadline -> DENY', true);
  } catch (e) {
    reportTest('Rem33.6 Shopkeeper cannot modify acceptDeadline -> DENY', false);
  }

  // Rem33.7 Legitimate shopkeeper status update still works -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_cust_a_for_sk_status_rem').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('Rem33.7 Legitimate shopkeeper status update still works -> ALLOW', true);
  } catch (e) {
    reportTest('Rem33.7 Legitimate shopkeeper status update still works -> ALLOW', false);
  }

  // Rem33.8 Legitimate rejection reason update still works -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_cust_a_for_sk_reject_rem').update({
      status: 'rejected',
      rejectionReason: 'Kitchen out of stock',
      updatedAt: new Date(),
    }));
    reportTest('Rem33.8 Legitimate rejection reason update still works -> ALLOW', true);
  } catch (e) {
    reportTest('Rem33.8 Legitimate rejection reason update still works -> ALLOW', false);
  }

  // Rem33.9 Legitimate delivery-person update still works -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_cust_a_for_sk_delivery_rem').update({
      status: 'delivered',
      deliveryPersonId: 'dp_99',
      deliveryPersonName: 'Suresh Kumar',
      updatedAt: new Date(),
    }));
    reportTest('Rem33.9 Legitimate delivery-person update still works -> ALLOW', true);
  } catch (e) {
    reportTest('Rem33.9 Legitimate delivery-person update still works -> ALLOW', false);
  }

  // Rem33.10 Customer cancellation remains functional -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('orders').doc('order_cust_a_for_cancel_rem').update({
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('Rem33.10 Customer cancellation remains functional -> ALLOW', true);
  } catch (e) {
    reportTest('Rem33.10 Customer cancellation remains functional -> ALLOW', false);
  }

  // Rem33.11 Customer still cannot modify lifecycle timestamps directly -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptedAt: new Date(),
    }));
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      deliveredAt: new Date(),
    }));
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      deliveryDeadline: new Date(),
    }));
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptDeadline: new Date(),
    }));
    reportTest('Rem33.11 Customer still cannot modify lifecycle timestamps directly -> DENY', true);
  } catch (e) {
    reportTest('Rem33.11 Customer still cannot modify lifecycle timestamps directly -> DENY', false);
  }

  // Rem33.12 Cross-shop lifecycle manipulation remains denied -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_b_shop_b').update({
      status: 'accepted',
      rejectionReason: 'Cross-shop tampering',
      updatedAt: new Date(),
    }));
    reportTest('Rem33.12 Cross-shop lifecycle manipulation remains denied -> DENY', true);
  } catch (e) {
    reportTest('Rem33.12 Cross-shop lifecycle manipulation remains denied -> DENY', false);
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
