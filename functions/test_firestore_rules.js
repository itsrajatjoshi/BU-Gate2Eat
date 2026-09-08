/**
 * YummBU / BU Gate2Eat — Firestore Security Rules Unit Tests
 * 
 * Checkpoint 3.1: Default-Deny Firestore Rules
 * 
 * Tests against live Firebase Firestore Emulator using @firebase/rules-unit-testing.
 * Proves that database-level authorization rejects unauthorized direct Firebase API calls
 * regardless of client identity, route guards, or service layer abstractions.
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
}

async function runRulesSecuritySuite() {
  console.log('=================================================================');
  console.log('  CHECKPOINT 3.1: FIRESTORE SECURITY RULES (DEFAULT-DENY SUITE)  ');
  console.log('=================================================================\n');

  // ─── 1. ANONYMOUS ACCESS TESTS (DEFAULT DENY) ──────────────────────
  console.log('--- 1. Anonymous Access Tests ---');

  // 1.1 Anonymous cannot read orders
  try {
    await assertFails(unauthDb.collection('orders').doc('order_1').get());
    reportTest('1.1 Anonymous -> protected orders read = DENY', true);
  } catch (e) {
    reportTest('1.1 Anonymous -> protected orders read = DENY', false);
  }

  // 1.2 Anonymous cannot write orders
  try {
    await assertFails(unauthDb.collection('orders').doc('order_1').set({
      orderId: 'order_1',
      shopId: 'shop_a',
      customerId: 'anon',
      status: 'placed',
      totalAmount: 100,
    }));
    reportTest('1.2 Anonymous -> protected orders write = DENY', true);
  } catch (e) {
    reportTest('1.2 Anonymous -> protected orders write = DENY', false);
  }

  // 1.3 Anonymous cannot delete orders
  try {
    await assertFails(unauthDb.collection('orders').doc('order_1').delete());
    reportTest('1.3 Anonymous -> protected orders delete = DENY', true);
  } catch (e) {
    reportTest('1.3 Anonymous -> protected orders delete = DENY', false);
  }

  // 1.4 Anonymous cannot read shop stats
  try {
    await assertFails(unauthDb.collection('shopStats').doc('shop_a').get());
    reportTest('1.4 Anonymous -> protected shopStats read = DENY', true);
  } catch (e) {
    reportTest('1.4 Anonymous -> protected shopStats read = DENY', false);
  }

  // 1.5 Anonymous cannot write shop stats
  try {
    await assertFails(unauthDb.collection('shopStats').doc('shop_a').set({ count: 10 }));
    reportTest('1.5 Anonymous -> protected shopStats write = DENY', true);
  } catch (e) {
    reportTest('1.5 Anonymous -> protected shopStats write = DENY', false);
  }

  // 1.6 Anonymous cannot read device tokens
  try {
    await assertFails(unauthDb.collection('deviceTokens').doc('token_1').get());
    reportTest('1.6 Anonymous -> protected deviceTokens read = DENY', true);
  } catch (e) {
    reportTest('1.6 Anonymous -> protected deviceTokens read = DENY', false);
  }

  // 1.7 Anonymous cannot delete device tokens
  try {
    await assertFails(unauthDb.collection('deviceTokens').doc('token_1').delete());
    reportTest('1.7 Anonymous -> protected deviceTokens delete = DENY', true);
  } catch (e) {
    reportTest('1.7 Anonymous -> protected deviceTokens delete = DENY', false);
  }

  // 1.8 Anonymous cannot read customer support queries
  try {
    await assertFails(unauthDb.collection('supportQueries').doc('query_1').get());
    reportTest('1.8 Anonymous -> protected supportQueries read = DENY', true);
  } catch (e) {
    reportTest('1.8 Anonymous -> protected supportQueries read = DENY', false);
  }

  // ─── 2. PUBLIC CATALOG BROWSING TESTS ───────────────────────────────
  console.log('\n--- 2. Public Catalog Browsing Tests ---');

  // 2.1 Anonymous can read shops catalog
  try {
    await assertSucceeds(unauthDb.collection('shops').doc('shop_a').get());
    reportTest('2.1 Anonymous can read /shops/{shopId} = ALLOW', true);
  } catch (e) {
    reportTest('2.1 Anonymous can read /shops/{shopId} = ALLOW', false);
  }

  // 2.2 Anonymous can read categories
  try {
    await assertSucceeds(unauthDb.collection('shops').doc('shop_a').collection('categories').doc('cat_1').get());
    reportTest('2.2 Anonymous can read /shops/{shopId}/categories/{catId} = ALLOW', true);
  } catch (e) {
    reportTest('2.2 Anonymous can read /shops/{shopId}/categories/{catId} = ALLOW', false);
  }

  // 2.3 Anonymous can read menu items
  try {
    await assertSucceeds(unauthDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_1').get());
    reportTest('2.3 Anonymous can read /shops/{shopId}/menuItems/{itemId} = ALLOW', true);
  } catch (e) {
    reportTest('2.3 Anonymous can read /shops/{shopId}/menuItems/{itemId} = ALLOW', false);
  }

  // 2.4 Customer can read shops catalog
  try {
    await assertSucceeds(customerDb.collection('shops').doc('shop_a').get());
    reportTest('2.4 Customer can read /shops/{shopId} = ALLOW', true);
  } catch (e) {
    reportTest('2.4 Customer can read /shops/{shopId} = ALLOW', false);
  }

  // 2.5 Shopkeeper can read shops catalog
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').get());
    reportTest('2.5 Shopkeeper can read /shops/{shopId} = ALLOW', true);
  } catch (e) {
    reportTest('2.5 Shopkeeper can read /shops/{shopId} = ALLOW', false);
  }

  // 2.6 Admin can read shops catalog
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').get());
    reportTest('2.6 Admin can read /shops/{shopId} = ALLOW', true);
  } catch (e) {
    reportTest('2.6 Admin can read /shops/{shopId} = ALLOW', false);
  }

  // 2.7 Anonymous can read app config
  try {
    await assertSucceeds(unauthDb.collection('config').doc('app_config').get());
    reportTest('2.7 Anonymous can read /config/app_config = ALLOW', true);
  } catch (e) {
    reportTest('2.7 Anonymous can read /config/app_config = ALLOW', false);
  }

  // ─── 3. PUBLIC CATALOG WRITE DENIAL (NO GLOBAL/PUBLIC WRITES) ───────
  console.log('\n--- 3. Public Catalog Write Denial Tests ---');

  // 3.1 Anonymous cannot write shops
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_new').set({ name: 'Hacked Shop' }));
    reportTest('3.1 Anonymous cannot write /shops/{shopId} = DENY', true);
  } catch (e) {
    reportTest('3.1 Anonymous cannot write /shops/{shopId} = DENY', false);
  }

  // 3.2 Anonymous cannot delete shops
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_a').delete());
    reportTest('3.2 Anonymous cannot delete /shops/{shopId} = DENY', true);
  } catch (e) {
    reportTest('3.2 Anonymous cannot delete /shops/{shopId} = DENY', false);
  }

  // 3.3 Customer cannot write shops
  try {
    await assertFails(customerDb.collection('shops').doc('shop_new').set({ name: 'Customer Shop' }));
    reportTest('3.3 Customer cannot write /shops/{shopId} = DENY', true);
  } catch (e) {
    reportTest('3.3 Customer cannot write /shops/{shopId} = DENY', false);
  }

  // 3.4 Customer cannot write menu items
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_x').set({
      name: 'Free Food',
      price: 0,
    }));
    reportTest('3.4 Customer cannot write /menuItems/{itemId} = DENY', true);
  } catch (e) {
    reportTest('3.4 Customer cannot write /menuItems/{itemId} = DENY', false);
  }

  // 3.5 Shopkeeper cannot delete shop (Phase 3.1 baseline deny)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').delete());
    reportTest('3.5 Shopkeeper cannot delete /shops/{shopId} = DENY', true);
  } catch (e) {
    reportTest('3.5 Shopkeeper cannot delete /shops/{shopId} = DENY', false);
  }

  // 3.6 Anonymous cannot write config
  try {
    await assertFails(unauthDb.collection('config').doc('app_config').set({ maintenance: true }));
    reportTest('3.6 Anonymous cannot write /config/app_config = DENY', true);
  } catch (e) {
    reportTest('3.6 Anonymous cannot write /config/app_config = DENY', false);
  }

  // ─── 4. CUSTOMER BOUNDARY TESTS ─────────────────────────────────────
  console.log('\n--- 4. Customer Boundary Tests ---');

  // 4.1 Customer cannot read support queries
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_1').get());
    reportTest('4.1 Customer -> privileged supportQueries read = DENY', true);
  } catch (e) {
    reportTest('4.1 Customer -> privileged supportQueries read = DENY', false);
  }

  // 4.2 Customer cannot read shop stats
  try {
    await assertFails(customerDb.collection('shopStats').doc('shop_a').get());
    reportTest('4.2 Customer -> privileged shopStats read = DENY', true);
  } catch (e) {
    reportTest('4.2 Customer -> privileged shopStats read = DENY', false);
  }

  // 4.3 Customer cannot write shop stats
  try {
    await assertFails(customerDb.collection('shopStats').doc('shop_a').set({ totalOrders: 0 }));
    reportTest('4.3 Customer -> privileged shopStats write = DENY', true);
  } catch (e) {
    reportTest('4.3 Customer -> privileged shopStats write = DENY', false);
  }

  // 4.4 Customer cannot write arbitrary collections
  try {
    await assertFails(customerDb.collection('auditLogs').doc('log_1').set({ event: 'hacked' }));
    reportTest('4.4 Customer -> arbitrary collection write = DENY', true);
  } catch (e) {
    reportTest('4.4 Customer -> arbitrary collection write = DENY', false);
  }

  // 4.5 Customer cannot write to users collection
  try {
    await assertFails(customerDb.collection('users').doc('user_other').set({ role: 'admin' }));
    reportTest('4.5 Customer -> arbitrary users collection write = DENY', true);
  } catch (e) {
    reportTest('4.5 Customer -> arbitrary users collection write = DENY', false);
  }

  // ─── 5. SHOPKEEPER BOUNDARY TESTS ───────────────────────────────────
  console.log('\n--- 5. Shopkeeper Boundary Tests ---');

  // 5.1 Shopkeeper cannot read support queries
  try {
    await assertFails(shopkeeperADb.collection('supportQueries').doc('query_1').get());
    reportTest('5.1 Shopkeeper -> privileged supportQueries read = DENY', true);
  } catch (e) {
    reportTest('5.1 Shopkeeper -> privileged supportQueries read = DENY', false);
  }

  // 5.2 Shopkeeper cannot write arbitrary privileged collections
  try {
    await assertFails(shopkeeperADb.collection('auditLogs').doc('log_1').set({ event: 'reset' }));
    reportTest('5.2 Shopkeeper -> arbitrary privileged collection write = DENY', true);
  } catch (e) {
    reportTest('5.2 Shopkeeper -> arbitrary privileged collection write = DENY', false);
  }

  // 5.3 Shopkeeper cannot access arbitrary unspecified collection
  try {
    await assertFails(shopkeeperADb.collection('adminSettings').doc('system').get());
    reportTest('5.3 Shopkeeper -> arbitrary collection access = DENY', true);
  } catch (e) {
    reportTest('5.3 Shopkeeper -> arbitrary collection access = DENY', false);
  }

  // ─── 6. ADMIN BOUNDARY & STRICT CLAIM TESTS ─────────────────────────
  console.log('\n--- 6. Admin Boundary & Strict Claim Tests ---');

  // 6.1 Valid admin claim -> allowed where admin policy is intentionally allowed
  try {
    await assertSucceeds(adminDb.collection('supportQueries').doc('query_1').get());
    reportTest('6.1 Valid admin claim {role: "admin"} -> allowed = ALLOW', true);
  } catch (e) {
    reportTest('6.1 Valid admin claim {role: "admin"} -> allowed = ALLOW', false);
  }

  // 6.2 Customer with admin-looking phone data -> denied
  try {
    await assertFails(customerWithAdminPhoneDb.collection('supportQueries').doc('query_1').get());
    reportTest('6.2 Customer with admin-looking phone data -> DENY', true);
  } catch (e) {
    reportTest('6.2 Customer with admin-looking phone data -> DENY', false);
  }

  // 6.3 Shopkeeper with admin-looking phone data -> denied
  try {
    await assertFails(shopkeeperWithAdminPhoneDb.collection('supportQueries').doc('query_1').get());
    reportTest('6.3 Shopkeeper with admin-looking phone data -> DENY', true);
  } catch (e) {
    reportTest('6.3 Shopkeeper with admin-looking phone data -> DENY', false);
  }

  // 6.4 Authenticated user with admin: true but role != admin -> denied
  try {
    await assertFails(userWithAdminFlagDb.collection('supportQueries').doc('query_1').get());
    reportTest('6.4 Authenticated user with admin: true but role != admin -> DENY', true);
  } catch (e) {
    reportTest('6.4 Authenticated user with admin: true but role != admin -> DENY', false);
  }

  // 6.5 Authenticated user with former admin phone but role != admin -> denied
  try {
    await assertFails(userWithAdminPhoneOnlyDb.collection('supportQueries').doc('query_1').get());
    reportTest('6.5 User with former admin phone but missing role claim -> DENY', true);
  } catch (e) {
    reportTest('6.5 User with former admin phone but missing role claim -> DENY', false);
  }

  // 6.6 Missing role -> denied
  try {
    await assertFails(userWithMissingRoleDb.collection('supportQueries').doc('query_1').get());
    reportTest('6.6 Authenticated user with missing role claim -> DENY', true);
  } catch (e) {
    reportTest('6.6 Authenticated user with missing role claim -> DENY', false);
  }

  // 6.7 role: customer -> denied for admin-only resource
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_1').get());
    reportTest('6.7 role: customer -> denied for admin-only resource = DENY', true);
  } catch (e) {
    reportTest('6.7 role: customer -> denied for admin-only resource = DENY', false);
  }

  // 6.8 role: shopkeeper -> denied for admin-only resource
  try {
    await assertFails(shopkeeperADb.collection('supportQueries').doc('query_1').get());
    reportTest('6.8 role: shopkeeper -> denied for admin-only resource = DENY', true);
  } catch (e) {
    reportTest('6.8 role: shopkeeper -> denied for admin-only resource = DENY', false);
  }

  // 6.9 Admin does NOT receive blanket access to arbitrary collections (deny-by-default preserved)
  try {
    await assertFails(adminDb.collection('unconfigured_collection').doc('doc_1').get());
    reportTest('6.9 Admin does NOT receive blanket access (deny-by-default preserved) = DENY', true);
  } catch (e) {
    reportTest('6.9 Admin does NOT receive blanket access (deny-by-default preserved) = DENY', false);
  }

  // 6.10 Admin write to unconfigured collection is denied
  try {
    await assertFails(adminDb.collection('unconfigured_collection').doc('doc_1').set({ val: 1 }));
    reportTest('6.10 Admin write to unconfigured collection = DENY', true);
  } catch (e) {
    reportTest('6.10 Admin write to unconfigured collection = DENY', false);
  }

  // ─── 7. CRITICAL NEGATIVE TEST: DIRECT FIRESTORE API BYPASS ─────────
  console.log('\n--- 7. Critical Negative Test: Direct Client API Bypass ---');

  // 7.1 Direct API attacker attempting to read another customer's protected order data
  try {
    await assertFails(attackerDb.collection('orders').doc('victim_order_123').get());
    reportTest('7.1 Authenticated attacker direct API read to orders = DENY', true);
  } catch (e) {
    reportTest('7.1 Authenticated attacker direct API read to orders = DENY', false);
  }

  // 7.2 Direct API attacker attempting to inject shopkeeper role and write to shopStats
  try {
    await assertFails(attackerDb.collection('shopStats').doc('shop_a').set({ revenue: 0 }));
    reportTest('7.2 Authenticated attacker direct API write to shopStats = DENY', true);
  } catch (e) {
    reportTest('7.2 Authenticated attacker direct API write to shopStats = DENY', false);
  }

  // 7.3 Direct API attacker attempting to delete shops
  try {
    await assertFails(attackerDb.collection('shops').doc('shop_a').delete());
    reportTest('7.3 Authenticated attacker direct API delete to shops = DENY', true);
  } catch (e) {
    reportTest('7.3 Authenticated attacker direct API delete to shops = DENY', false);
  }

  // ─── 8. UNIVERSAL FALLTHROUGH DENIAL ────────────────────────────────
  console.log('\n--- 8. Universal Fallthrough Denial Tests ---');

  // 8.1 Random path anonymous read denied
  try {
    await assertFails(unauthDb.collection('random_secret_vault').doc('key').get());
    reportTest('8.1 Anonymous read on unknown collection = DENY', true);
  } catch (e) {
    reportTest('8.1 Anonymous read on unknown collection = DENY', false);
  }

  // 8.2 Random path anonymous write denied
  try {
    await assertFails(unauthDb.collection('random_secret_vault').doc('key').set({ secret: 'stolen' }));
    reportTest('8.2 Anonymous write on unknown collection = DENY', true);
  } catch (e) {
    reportTest('8.2 Anonymous write on unknown collection = DENY', false);
  }

  // 8.3 Random path authenticated customer write denied
  try {
    await assertFails(customerDb.collection('internal_metrics').doc('m1').set({ val: 99 }));
    reportTest('8.3 Customer write on unknown collection = DENY', true);
  } catch (e) {
    reportTest('8.3 Customer write on unknown collection = DENY', false);
  }

  // 8.4 Random path authenticated shopkeeper write denied
  try {
    await assertFails(shopkeeperADb.collection('internal_metrics').doc('m1').set({ val: 99 }));
    reportTest('8.4 Shopkeeper write on unknown collection = DENY', true);
  } catch (e) {
    reportTest('8.4 Shopkeeper write on unknown collection = DENY', false);
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
