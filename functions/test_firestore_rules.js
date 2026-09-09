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

    // ── Phase 5.1 Order State Machine Seeds ──
    await adminFs.collection('orders').doc('order_osm_placed_for_accept').set({
      ...orderDataA,
      orderId: 'order_osm_placed_for_accept',
      status: 'placed',
    });
    await adminFs.collection('orders').doc('order_osm_placed_for_reject').set({
      ...orderDataA,
      orderId: 'order_osm_placed_for_reject',
      status: 'placed',
    });
    await adminFs.collection('orders').doc('order_osm_placed_for_cancel').set({
      ...orderDataA,
      orderId: 'order_osm_placed_for_cancel',
      status: 'placed',
    });
    await adminFs.collection('orders').doc('order_osm_accepted_for_deliver').set({
      ...orderDataA,
      orderId: 'order_osm_accepted_for_deliver',
      status: 'accepted',
      acceptedAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_osm_placed_for_invalid').set({
      ...orderDataA,
      orderId: 'order_osm_placed_for_invalid',
      status: 'placed',
    });
    await adminFs.collection('orders').doc('order_osm_accepted_for_invalid').set({
      ...orderDataA,
      orderId: 'order_osm_accepted_for_invalid',
      status: 'accepted',
      acceptedAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_osm_terminal_delivered').set({
      ...orderDataA,
      orderId: 'order_osm_terminal_delivered',
      status: 'delivered',
      deliveredAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_osm_terminal_rejected').set({
      ...orderDataA,
      orderId: 'order_osm_terminal_rejected',
      status: 'rejected',
      rejectedAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_osm_terminal_cancelled').set({
      ...orderDataA,
      orderId: 'order_osm_terminal_cancelled',
      status: 'cancelled',
      cancelledAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_osm_terminal_expired').set({
      ...orderDataA,
      orderId: 'order_osm_terminal_expired',
      status: 'delivery_expired',
    });

    // ── Phase 5.2 Role-Based State Transition Seeds ──
    await adminFs.collection('orders').doc('order_rbt_placed_cust').set({
      ...orderDataA,
      orderId: 'order_rbt_placed_cust',
      status: 'placed',
    });
    await adminFs.collection('orders').doc('order_rbt_accepted_cust').set({
      ...orderDataA,
      orderId: 'order_rbt_accepted_cust',
      status: 'accepted',
      acceptedAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_rbt_placed_admin').set({
      ...orderDataA,
      orderId: 'order_rbt_placed_admin',
      status: 'placed',
    });
    await adminFs.collection('orders').doc('order_rbt_accepted_admin').set({
      ...orderDataA,
      orderId: 'order_rbt_accepted_admin',
      status: 'accepted',
      acceptedAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_rbt_placed_sk').set({
      ...orderDataA,
      orderId: 'order_rbt_placed_sk',
      status: 'placed',
    });

    // ── Phase 5.3 Dedicated Seed Orders for Immutability Testing ──
    const orderDataIMF = {
      orderId: 'order_imf_placed_cust',
      customerId: 'customer_a',
      customerName: 'Customer A',
      customerPhone: '+919876543210',
      shopId: 'shop_a',
      shopName: 'Shop A',
      status: 'placed',
      totalAmount: 250,
      grandTotal: 250,
      subtotal: 220,
      deliveryCharges: 30,
      totalItems: 1,
      orderMethod: 'app',
      specialInstructions: 'Extra cheese',
      deliveryNote: 'Gate 2 delivery',
      items: [
        {
          itemId: 'item_1',
          menuItemId: 'item_1',
          name: 'Burger',
          price: 250,
          quantity: 1,
          subtotal: 250,
          selectedOptions: [],
        }
      ],
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    await adminFs.collection('orders').doc('order_imf_placed_cust').set(orderDataIMF);
    await adminFs.collection('orders').doc('order_imf_accepted_cust').set({
      ...orderDataIMF,
      orderId: 'order_imf_accepted_cust',
      status: 'accepted',
      acceptedAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_imf_placed_sk').set({
      ...orderDataIMF,
      orderId: 'order_imf_placed_sk',
    });
    await adminFs.collection('orders').doc('order_imf_accepted_sk').set({
      ...orderDataIMF,
      orderId: 'order_imf_accepted_sk',
      status: 'accepted',
      acceptedAt: new Date(),
    });
    await adminFs.collection('orders').doc('order_imf_placed_admin').set({
      ...orderDataIMF,
      orderId: 'order_imf_placed_admin',
    });

    // ── Phase 3.4 Sensitive Collections Seeds ──
    // 1. shopStats
    await adminFs.collection('shopStats').doc('shop_a').set({
      shopId: 'shop_a',
      shopName: 'Shop A',
      totalOrders: 10,
      deliveredOrders: 8,
      cancelledOrders: 1,
      whatsappOrders: 5,
      revenue: 2500,
      updatedAt: new Date(),
    });
    await adminFs.collection('shopStats').doc('shop_b').set({
      shopId: 'shop_b',
      shopName: 'Shop B',
      totalOrders: 5,
      deliveredOrders: 4,
      cancelledOrders: 0,
      whatsappOrders: 2,
      revenue: 1200,
      updatedAt: new Date(),
    });
    await adminFs.collection('shopStats').doc('shop_a').collection('monthlyStats').doc('2026-09').set({
      shopId: 'shop_a',
      monthKey: '2026-09',
      totalOrders: 10,
      updatedAt: new Date(),
    });
    await adminFs.collection('shopStats').doc('shop_b').collection('monthlyStats').doc('2026-09').set({
      shopId: 'shop_b',
      monthKey: '2026-09',
      totalOrders: 5,
      updatedAt: new Date(),
    });

    // 2. deviceTokens
    await adminFs.collection('deviceTokens').doc('token_cust_a').set({
      token: 'token_cust_a',
      uid: 'customer_a',
      customerId: 'customer_a',
      role: 'customer',
      phone: '+919876543210',
      platform: 'android',
      updatedAt: new Date(),
    });
    await adminFs.collection('deviceTokens').doc('token_cust_b').set({
      token: 'token_cust_b',
      uid: 'customer_b',
      customerId: 'customer_b',
      role: 'customer',
      phone: '+919876543211',
      platform: 'ios',
      updatedAt: new Date(),
    });
    await adminFs.collection('deviceTokens').doc('token_sk_a').set({
      token: 'token_sk_a',
      uid: 'shopkeeper_a',
      role: 'shopkeeper',
      shopId: 'shop_a',
      phone: '+919876543212',
      platform: 'android',
      updatedAt: new Date(),
    });
    await adminFs.collection('deviceTokens').doc('token_for_delete').set({
      token: 'token_for_delete',
      uid: 'customer_a',
      customerId: 'customer_a',
      role: 'customer',
      phone: '+919876543210',
      platform: 'android',
      updatedAt: new Date(),
    });

    // 3. supportQueries
    await adminFs.collection('supportQueries').doc('query_1').set({
      id: 'query_1',
      name: 'Regression Inquiry',
      query: 'Inquiry text for regression',
      phone: '+918078643910',
      phoneNumber: '+918078643910',
      customerId: 'some_other_customer',
      status: 'unread',
      createdAt: new Date(),
    });
    await adminFs.collection('supportQueries').doc('query_cust_a').set({
      id: 'query_cust_a',
      name: 'Customer A Support',
      query: 'Customer A problem description',
      phone: '+919876543210',
      phoneNumber: '+919876543210',
      customerId: 'customer_a',
      status: 'unread',
      createdAt: new Date(),
    });
    await adminFs.collection('supportQueries').doc('query_cust_b').set({
      id: 'query_cust_b',
      name: 'Customer B Support',
      query: 'Customer B problem description',
      phone: '+919876543211',
      phoneNumber: '+919876543211',
      customerId: 'customer_b',
      status: 'unread',
      createdAt: new Date(),
    });

    // 4. users & profiles
    await adminFs.collection('users').doc('customer_a').set({
      uid: 'customer_a',
      name: 'Customer A User Profile',
      phone: '+919876543210',
      createdAt: new Date(),
    });
    await adminFs.collection('users').doc('customer_b').set({
      uid: 'customer_b',
      name: 'Customer B User Profile',
      phone: '+919876543211',
      createdAt: new Date(),
    });
    await adminFs.collection('profiles').doc('customer_a').set({
      uid: 'customer_a',
      displayName: 'Customer A Public Profile',
      updatedAt: new Date(),
    });
    await adminFs.collection('profiles').doc('customer_b').set({
      uid: 'customer_b',
      displayName: 'Customer B Public Profile',
      updatedAt: new Date(),
    });

    // 5. Server-only collections
    await adminFs.collection('_authChallenges').doc('challenge_1').set({
      phoneHash: 'hash_phone_1',
      otpHash: 'hash_otp_1',
      expiresAt: new Date(Date.now() + 600000),
    });
    await adminFs.collection('auditLogs').doc('audit_1').set({
      event: 'platform_maintenance',
      actor: 'system',
      timestamp: new Date(),
    });
    await adminFs.collection('internal_metrics').doc('metric_1').set({
      activeNodes: 4,
      timestamp: new Date(),
    });
    await adminFs.collection('adminSettings').doc('system').set({
      maintenanceMode: false,
      version: '1.0.0',
    });

    // 6. Dedicated seeds for Checkpoint 3.5 Field-Level Attack Tests
    const fldCreated = new Date('2026-09-01T10:00:00Z');
    await adminFs.collection('shops').doc('shop_a').update({
      createdAt: fldCreated,
      updatedAt: fldCreated,
    });
    await adminFs.collection('shops').doc('shop_b').update({
      createdAt: fldCreated,
      updatedAt: fldCreated,
    });
    await adminFs.collection('shops').doc('shop_a').collection('categories').doc('cat_a_fld').set({
      name: 'Cat A Fld',
      shopId: 'shop_a',
      sortOrder: 1,
      isActive: true,
    });
    await adminFs.collection('shops').doc('shop_a').collection('menuItems').doc('item_a_fld').set({
      name: 'Item A Fld',
      price: 100,
      shopId: 'shop_a',
      isAvailable: true,
      sortOrder: 1,
    });
    await adminFs.collection('orders').doc('order_cust_a_fld_cancel').set({
      orderId: 'order_cust_a_fld_cancel',
      customerId: 'customer_a',
      customerName: 'Customer A',
      customerPhone: '+919876543210',
      shopId: 'shop_a',
      shopName: 'Shop A',
      status: 'placed',
      totalAmount: 300,
      subtotal: 300,
      grandTotal: 300,
      deliveryCharges: 0,
      items: [{ itemId: 'item_1', name: 'Burger', price: 300, quantity: 1 }],
      acceptDeadline: new Date('2026-09-08T12:00:00Z'),
      createdAt: fldCreated,
      updatedAt: fldCreated,
    });
    await adminFs.collection('orders').doc('order_cust_a_fld_sk').set({
      orderId: 'order_cust_a_fld_sk',
      customerId: 'customer_a',
      customerName: 'Customer A',
      customerPhone: '+919876543210',
      shopId: 'shop_a',
      shopName: 'Shop A',
      status: 'placed',
      totalAmount: 300,
      subtotal: 300,
      grandTotal: 300,
      deliveryCharges: 0,
      items: [{ itemId: 'item_1', name: 'Burger', price: 300, quantity: 1 }],
      acceptDeadline: new Date('2026-09-08T12:00:00Z'),
      createdAt: fldCreated,
      updatedAt: fldCreated,
    });
    await adminFs.collection('orders').doc('order_cust_a_fld_admin').set({
      orderId: 'order_cust_a_fld_admin',
      customerId: 'customer_a',
      customerName: 'Customer A',
      customerPhone: '+919876543210',
      shopId: 'shop_a',
      shopName: 'Shop A',
      status: 'placed',
      totalAmount: 300,
      subtotal: 300,
      grandTotal: 300,
      deliveryCharges: 0,
      items: [{ itemId: 'item_1', name: 'Burger', price: 300, quantity: 1 }],
      acceptDeadline: new Date('2026-09-08T12:00:00Z'),
      createdAt: fldCreated,
      updatedAt: fldCreated,
    });
    await adminFs.collection('deviceTokens').doc('token_cust_a_fld').set({
      token: 'token_cust_a_fld',
      uid: 'customer_a',
      customerId: 'customer_a',
      role: 'customer',
      phone: '+919876543210',
      platform: 'android',
      updatedAt: fldCreated,
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

  // O.7 Customer direct Firestore order create -> DENY (Phase 4.1 Server-Authoritative Boundary)
  try {
    // 1. Normal customer direct creation -> DENY
    await assertFails(customerDb.collection('orders').doc('order_new_cust_a').set({
      orderId: 'order_new_cust_a',
      customerId: 'customer_a',
      shopId: 'shop_a',
      status: 'placed',
      totalAmount: 200,
      items: [{ itemId: 'item_1', name: 'Burger', price: 200, quantity: 1 }],
      createdAt: new Date(),
    }));

    // 2. Malicious client direct creation with forged financial totals -> DENY
    await assertFails(customerDb.collection('orders').doc('order_attacker_direct').set({
      orderId: 'order_attacker_direct',
      customerId: 'customer_a',
      shopId: 'shop_a',
      items: [{ itemId: 'item_1', name: 'Burger', price: 1, quantity: 1 }],
      subtotal: 1,
      deliveryCharges: 0,
      grandTotal: 1,
      totalAmount: 1,
      status: 'placed',
      createdAt: new Date(),
    }));

    // 3. Admin client direct creation via Client SDK -> DENY
    await assertFails(adminDb.collection('orders').doc('order_admin_client_direct').set({
      orderId: 'order_admin_client_direct',
      customerId: 'customer_a',
      shopId: 'shop_a',
      status: 'placed',
      totalAmount: 100,
      items: [],
    }));

    // 4. Trusted backend Admin SDK creation -> SUCCESS
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await assertSucceeds(context.firestore().collection('orders').doc('order_admin_sdk_backend').set({
        orderId: 'order_admin_sdk_backend',
        customerId: 'customer_a',
        shopId: 'shop_a',
        status: 'placed',
        totalAmount: 200,
        items: [{ itemId: 'item_1', name: 'Burger', price: 200, quantity: 1 }],
        createdAt: new Date(),
      }));
    });

    reportTest('O.7 Direct client order creation blocked & Admin SDK allowed -> VERIFIED', true);
  } catch (e) {
    reportTest('O.7 Direct client order creation blocked & Admin SDK allowed -> VERIFIED', false);
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

  // ═════════════════════════════════════════════════════════════════════
  // CHECKPOINT 3.4 SENSITIVE COLLECTIONS REMEDIATION SUITE (Sens.1 - Sens.38)
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n--- Phase 3.4: Sensitive Collections Suite (Sens.1 - Sens.38) ---');

  // ── 1. shopStats Server-Owned Tests (Sens.1 - Sens.10) ──
  // Sens.1: Shopkeeper reads own stats -> ALLOW
  try {
    const p1 = assertSucceeds(shopkeeperADb.collection('shopStats').doc('shop_a').get());
    const p2 = assertSucceeds(shopkeeperADb.collection('shopStats').doc('shop_a').collection('monthlyStats').doc('2026-09').get());
    await Promise.all([p1, p2]);
    reportTest('Sens.1 Shopkeeper reads own stats -> ALLOW', true);
  } catch (e) {
    reportTest('Sens.1 Shopkeeper reads own stats -> ALLOW', false);
  }

  // Sens.2: Shopkeeper reads foreign stats -> DENY
  try {
    const p1 = assertFails(shopkeeperADb.collection('shopStats').doc('shop_b').get());
    const p2 = assertFails(shopkeeperADb.collection('shopStats').doc('shop_b').collection('monthlyStats').doc('2026-09').get());
    await Promise.all([p1, p2]);
    reportTest('Sens.2 Shopkeeper reads foreign stats -> DENY', true);
  } catch (e) {
    reportTest('Sens.2 Shopkeeper reads foreign stats -> DENY', false);
  }

  // Sens.3: Customer reads stats -> DENY
  try {
    const p1 = assertFails(customerDb.collection('shopStats').doc('shop_a').get());
    const p2 = assertFails(customerDb.collection('shopStats').doc('shop_b').get());
    await Promise.all([p1, p2]);
    reportTest('Sens.3 Customer reads stats -> DENY', true);
  } catch (e) {
    reportTest('Sens.3 Customer reads stats -> DENY', false);
  }

  // Sens.4: Anonymous reads stats -> DENY
  try {
    await assertFails(unauthDb.collection('shopStats').doc('shop_a').get());
    reportTest('Sens.4 Anonymous reads stats -> DENY', true);
  } catch (e) {
    reportTest('Sens.4 Anonymous reads stats -> DENY', false);
  }

  // Sens.5: Shopkeeper creates stats -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shopStats').doc('shop_a_new').set({ shopId: 'shop_a_new', totalOrders: 0 }));
    reportTest('Sens.5 Shopkeeper creates stats -> DENY', true);
  } catch (e) {
    reportTest('Sens.5 Shopkeeper creates stats -> DENY', false);
  }

  // Sens.6: Shopkeeper updates stats -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shopStats').doc('shop_a').update({ totalOrders: 99 }));
    reportTest('Sens.6 Shopkeeper updates stats -> DENY', true);
  } catch (e) {
    reportTest('Sens.6 Shopkeeper updates stats -> DENY', false);
  }

  // Sens.7: Shopkeeper modifies revenue/counters -> DENY
  try {
    const p1 = assertFails(shopkeeperADb.collection('shopStats').doc('shop_a').update({ revenue: 500000 }));
    const p2 = assertFails(shopkeeperADb.collection('shopStats').doc('shop_a').collection('monthlyStats').doc('2026-09').update({ totalOrders: 999 }));
    await Promise.all([p1, p2]);
    reportTest('Sens.7 Shopkeeper modifies revenue/counters -> DENY', true);
  } catch (e) {
    reportTest('Sens.7 Shopkeeper modifies revenue/counters -> DENY', false);
  }

  // Sens.8: Admin client creates stats -> DENY
  try {
    await assertFails(adminDb.collection('shopStats').doc('shop_admin_test').set({ totalOrders: 0 }));
    reportTest('Sens.8 Admin client creates stats -> DENY', true);
  } catch (e) {
    reportTest('Sens.8 Admin client creates stats -> DENY', false);
  }

  // Sens.9: Admin client updates stats -> DENY
  try {
    await assertFails(adminDb.collection('shopStats').doc('shop_a').update({ totalOrders: 99 }));
    reportTest('Sens.9 Admin client updates stats -> DENY', true);
  } catch (e) {
    reportTest('Sens.9 Admin client updates stats -> DENY', false);
  }

  // Sens.10: Client deletes stats -> DENY
  try {
    const p1 = assertFails(shopkeeperADb.collection('shopStats').doc('shop_a').delete());
    const p2 = assertFails(adminDb.collection('shopStats').doc('shop_a').delete());
    const p3 = assertFails(customerDb.collection('shopStats').doc('shop_a').delete());
    const p4 = assertFails(unauthDb.collection('shopStats').doc('shop_a').delete());
    await Promise.all([p1, p2, p3, p4]);
    reportTest('Sens.10 Delete -> DENY', true);
  } catch (e) {
    reportTest('Sens.10 Delete -> DENY', false);
  }

  // ── 2. Users / Profiles Field Protection Tests (Sens.11 - Sens.19) ──
  // Sens.11: User reads own profile -> ALLOW
  try {
    const p1 = assertSucceeds(customerDb.collection('users').doc('customer_a').get());
    const p2 = assertSucceeds(customerDb.collection('profiles').doc('customer_a').get());
    await Promise.all([p1, p2]);
    reportTest('Sens.11 User reads own profile -> ALLOW', true);
  } catch (e) {
    reportTest('Sens.11 User reads own profile -> ALLOW', false);
  }

  // Sens.12: User reads foreign profile -> DENY
  try {
    const p1 = assertFails(customerDb.collection('users').doc('customer_b').get());
    const p2 = assertFails(customerDb.collection('profiles').doc('customer_b').get());
    await Promise.all([p1, p2]);
    reportTest('Sens.12 User reads foreign profile -> DENY', true);
  } catch (e) {
    reportTest('Sens.12 User reads foreign profile -> DENY', false);
  }

  // Sens.13: User updates allowed display/profile field -> ALLOW
  try {
    const p1 = assertSucceeds(customerDb.collection('users').doc('customer_a').update({ displayName: 'Customer A Valid', updatedAt: new Date() }));
    const p2 = assertSucceeds(customerDb.collection('profiles').doc('customer_a').update({ displayName: 'Customer A Profile Nickname' }));
    await Promise.all([p1, p2]);
    reportTest('Sens.13 User updates allowed display/profile field -> ALLOW', true);
  } catch (e) {
    reportTest('Sens.13 User updates allowed display/profile field -> ALLOW', false);
  }

  // Sens.14: User modifies role -> DENY
  try {
    await assertFails(customerDb.collection('users').doc('customer_a').update({ role: 'admin' }));
    reportTest('Sens.14 User modifies role -> DENY', true);
  } catch (e) {
    reportTest('Sens.14 User modifies role -> DENY', false);
  }

  // Sens.15: User modifies shopId -> DENY
  try {
    await assertFails(customerDb.collection('users').doc('customer_a').update({ shopId: 'shop_b' }));
    reportTest('Sens.15 User modifies shopId -> DENY', true);
  } catch (e) {
    reportTest('Sens.15 User modifies shopId -> DENY', false);
  }

  // Sens.16: User modifies status -> DENY
  try {
    await assertFails(customerDb.collection('users').doc('customer_a').update({ status: 'banned' }));
    reportTest('Sens.16 User modifies status -> DENY', true);
  } catch (e) {
    reportTest('Sens.16 User modifies status -> DENY', false);
  }

  // Sens.17: User modifies phone -> DENY
  try {
    await assertFails(customerDb.collection('users').doc('customer_a').update({ phone: '+919999999999' }));
    reportTest('Sens.17 User modifies phone -> DENY', true);
  } catch (e) {
    reportTest('Sens.17 User modifies phone -> DENY', false);
  }

  // Sens.18: User modifies uid -> DENY
  try {
    await assertFails(customerDb.collection('users').doc('customer_a').update({ uid: 'other_uid' }));
    reportTest('Sens.18 User modifies uid -> DENY', true);
  } catch (e) {
    reportTest('Sens.18 User modifies uid -> DENY', false);
  }

  // Sens.19: User writes another user\'s profile -> DENY
  try {
    const p1 = assertFails(customerDb.collection('users').doc('customer_b').update({ displayName: 'Hacked' }));
    const p2 = assertFails(customerDb.collection('profiles').doc('customer_b').update({ displayName: 'Hacked' }));
    await Promise.all([p1, p2]);
    reportTest('Sens.19 User writes another user\'s profile -> DENY', true);
  } catch (e) {
    reportTest('Sens.19 User writes another user\'s profile -> DENY', false);
  }

  // ── 3. Support Queries Tests (Sens.20 - Sens.25) ──
  // Sens.20: Authenticated customer creates own query -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('supportQueries').doc('query_rem_good').set({
      name: 'Cust A',
      query: 'Legitimate Query',
      phone: '9876543210',
      phoneNumber: '9876543210',
      status: 'unread',
      customerId: 'customer_a',
    }));
    reportTest('Sens.20 Authenticated customer creates own query -> ALLOW', true);
  } catch (e) {
    reportTest('Sens.20 Authenticated customer creates own query -> ALLOW', false);
  }

  // Sens.21: Customer claims another customerId -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_rem_bad').set({
      name: 'Cust A',
      query: 'Spoofed Query',
      phone: '9876543210',
      phoneNumber: '9876543210',
      status: 'unread',
      customerId: 'customer_b',
    }));
    reportTest('Sens.21 Customer claims another customerId -> DENY', true);
  } catch (e) {
    reportTest('Sens.21 Customer claims another customerId -> DENY', false);
  }

  // Sens.22: Anonymous create -> DENY
  try {
    await assertFails(unauthDb.collection('supportQueries').doc('query_rem_anon').set({
      name: 'Anon',
      query: 'Anon Query',
      phone: '9876543210',
      phoneNumber: '9876543210',
      status: 'unread',
    }));
    reportTest('Sens.22 Anonymous create -> DENY', true);
  } catch (e) {
    reportTest('Sens.22 Anonymous create -> DENY', false);
  }

  // Sens.23: Customer reads foreign query -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_cust_b').get());
    reportTest('Sens.23 Customer reads foreign query -> DENY', true);
  } catch (e) {
    reportTest('Sens.23 Customer reads foreign query -> DENY', false);
  }

  // Sens.24: Customer updates query -> DENY
  try {
    const p1 = assertFails(customerDb.collection('supportQueries').doc('query_cust_a').update({ status: 'resolved' }));
    const p2 = assertFails(customerDb.collection('supportQueries').doc('query_cust_a').update({ customerId: 'customer_b' }));
    await Promise.all([p1, p2]);
    reportTest('Sens.24 Customer updates query -> DENY', true);
  } catch (e) {
    reportTest('Sens.24 Customer updates query -> DENY', false);
  }

  // Sens.25: Customer deletes query -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_cust_a').delete());
    reportTest('Sens.25 Customer deletes query -> DENY', true);
  } catch (e) {
    reportTest('Sens.25 Customer deletes query -> DENY', false);
  }

  // ── 4. deviceTokens Tests (Sens.26 - Sens.32) ──
  // Sens.26: Customer own token operation -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('deviceTokens').doc('token_new_a').set({
      token: 'token_new_a',
      uid: 'customer_a',
      customerId: 'customer_a',
      role: 'customer',
      platform: 'android',
    }));
    await assertSucceeds(customerDb.collection('deviceTokens').doc('token_new_a').get());
    await assertSucceeds(customerDb.collection('deviceTokens').doc('token_for_delete').delete());
    reportTest('Sens.26 Customer own token operation -> ALLOW', true);
  } catch (e) {
    reportTest('Sens.26 Customer own token operation -> ALLOW', false);
  }

  // Sens.27: Customer foreign token -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_b').get());
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_b').delete());
    reportTest('Sens.27 Customer foreign token -> DENY', true);
  } catch (e) {
    reportTest('Sens.27 Customer foreign token -> DENY', false);
  }

  // Sens.28: Customer token role/shop tampering -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_t1').set({
      token: 'token_t1',
      uid: 'customer_a',
      role: 'admin',
    }));
    await assertFails(customerDb.collection('deviceTokens').doc('token_t2').set({
      token: 'token_t2',
      uid: 'customer_a',
      role: 'customer',
      shopId: 'shop_a',
    }));
    await assertFails(customerDb.collection('deviceTokens').doc('token_t3').set({
      token: 'token_t3',
      uid: 'customer_b',
      role: 'customer',
    }));
    reportTest('Sens.28 Customer token role/shop tampering -> DENY', true);
  } catch (e) {
    reportTest('Sens.28 Customer token role/shop tampering -> DENY', false);
  }

  // Sens.29: Shopkeeper cross-shop token manipulation -> DENY
  try {
    await assertFails(shopkeeperADb.collection('deviceTokens').doc('token_sk_bad').set({
      token: 'token_sk_bad',
      uid: 'shopkeeper_a',
      role: 'shopkeeper',
      shopId: 'shop_b',
    }));
    await assertSucceeds(shopkeeperADb.collection('deviceTokens').doc('token_sk_ok').set({
      token: 'token_sk_ok',
      uid: 'shopkeeper_a',
      role: 'shopkeeper',
      shopId: 'shop_a',
    }));
    reportTest('Sens.29 Shopkeeper cross-shop token manipulation -> DENY', true);
  } catch (e) {
    reportTest('Sens.29 Shopkeeper cross-shop token manipulation -> DENY', false);
  }

  // Sens.30: Anonymous token access -> DENY
  try {
    await assertFails(unauthDb.collection('deviceTokens').doc('token_anon').set({
      token: 'token_anon',
      uid: 'anon',
      role: 'customer',
    }));
    await assertFails(unauthDb.collection('deviceTokens').doc('token_cust_a').get());
    await assertFails(unauthDb.collection('deviceTokens').doc('token_cust_a').delete());
    reportTest('Sens.30 Anonymous token access -> DENY', true);
  } catch (e) {
    reportTest('Sens.30 Anonymous token access -> DENY', false);
  }

  // Sens.31: Global token enumeration -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').get());
    await assertFails(shopkeeperADb.collection('deviceTokens').get());
    await assertFails(unauthDb.collection('deviceTokens').get());
    reportTest('Sens.31 Global token enumeration -> DENY', true);
  } catch (e) {
    reportTest('Sens.31 Global token enumeration -> DENY', false);
  }

  // Sens.32: Direct bypass: Token ID mismatch with payload -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('doc_id_123').set({
      token: 'different_token_456',
      uid: 'customer_a',
      role: 'customer',
    }));
    reportTest('Sens.32 Direct bypass: Token ID mismatch with payload -> DENY', true);
  } catch (e) {
    reportTest('Sens.32 Direct bypass: Token ID mismatch with payload -> DENY', false);
  }

  // ── 5. Server-Only Collections Tests (Sens.33 - Sens.34) ──
  // Sens.33: Client reads server-only collection -> DENY
  try {
    await assertFails(customerDb.collection('_authChallenges').doc('challenge_1').get());
    await assertFails(adminDb.collection('_authChallenges').doc('challenge_1').get());
    await assertFails(customerDb.collection('auditLogs').doc('audit_1').get());
    await assertFails(adminDb.collection('auditLogs').doc('audit_1').get());
    reportTest('Sens.33 Client reads server-only collection -> DENY', true);
  } catch (e) {
    reportTest('Sens.33 Client reads server-only collection -> DENY', false);
  }

  // Sens.34: Client writes server-only collection -> DENY
  try {
    await assertFails(customerDb.collection('_authChallenges').doc('challenge_bad').set({ fake: true }));
    await assertFails(adminDb.collection('_authChallenges').doc('challenge_bad').set({ fake: true }));
    await assertFails(customerDb.collection('internal_metrics').doc('m1').set({ hacked: true }));
    await assertFails(adminDb.collection('internal_metrics').doc('m1').set({ hacked: true }));
    reportTest('Sens.34 Client writes server-only collection -> DENY', true);
  } catch (e) {
    reportTest('Sens.34 Client writes server-only collection -> DENY', false);
  }

  // ── 6. Query Safety Tests (Sens.35 - Sens.38) ──
  // Sens.35: Query Safety: Customer scoped query on own support queries -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('supportQueries').where('customerId', '==', 'customer_a').get());
    reportTest('Sens.35 Query Safety: Customer scoped query on own support queries -> ALLOW', true);
  } catch (e) {
    reportTest('Sens.35 Query Safety: Customer scoped query on own support queries -> ALLOW', false);
  }

  // Sens.36: Query Safety: Customer unfiltered query on all support queries -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').get());
    reportTest('Sens.36 Query Safety: Customer unfiltered query on all support queries -> DENY', true);
  } catch (e) {
    reportTest('Sens.36 Query Safety: Customer unfiltered query on all support queries -> DENY', false);
  }

  // Sens.37: Query Safety: Admin unfiltered query on all shopStats -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shopStats').get());
    reportTest('Sens.37 Query Safety: Admin unfiltered query on all shopStats -> ALLOW', true);
  } catch (e) {
    reportTest('Sens.37 Query Safety: Admin unfiltered query on all shopStats -> ALLOW', false);
  }

  // Sens.38: Query Safety: Shopkeeper unfiltered query on all shopStats -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shopStats').get());
    reportTest('Sens.38 Query Safety: Shopkeeper unfiltered query on all shopStats -> DENY', true);
  } catch (e) {
    reportTest('Sens.38 Query Safety: Shopkeeper unfiltered query on all shopStats -> DENY', false);
  }

  // ═════════════════════════════════════════════════════════════════════
  // CHECKPOINT 3.5: FIELD-LEVEL RESTRICTIONS ATTACK MATRIX (Fld.1 - Fld.50)
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n=================================================================');
  console.log('  CHECKPOINT 3.5: FIELD-LEVEL RESTRICTIONS ATTACK MATRIX SUITE   ');
  console.log('=================================================================\n');

  // ── 1. Shops Field Restrictions (Fld.1 - Fld.6) ──
  // Fld.1: Shopkeeper updates allowed operational fields on own shop -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').update({
      isClosedOverride: true,
      openTime: '09:00',
      description: 'Updated description by shopkeeper',
      updatedAt: new Date(),
    }));
    reportTest('Fld.1 Shopkeeper updates allowed operational fields on own shop -> ALLOW', true);
  } catch (e) {
    reportTest('Fld.1 Shopkeeper updates allowed operational fields on own shop -> ALLOW', false);
  }

  // Fld.2: Shopkeeper attempts to mutate id or shopId on shop -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      id: 'shop_hacked',
    }));
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      shopId: 'shop_b',
    }));
    reportTest('Fld.2 Shopkeeper attempts to mutate id or shopId on shop -> DENY', true);
  } catch (e) {
    reportTest('Fld.2 Shopkeeper attempts to mutate id or shopId on shop -> DENY', false);
  }

  // Fld.3: Shopkeeper attempts to mutate createdAt on shop -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      createdAt: new Date('2020-01-01T00:00:00Z'),
    }));
    reportTest('Fld.3 Shopkeeper attempts to mutate createdAt on shop -> DENY', true);
  } catch (e) {
    reportTest('Fld.3 Shopkeeper attempts to mutate createdAt on shop -> DENY', false);
  }

  // Fld.4: Shopkeeper attempts to inject unauthorized role/security field on shop -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      role: 'admin',
    }));
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      ownerUid: 'attacker_uid',
    }));
    reportTest('Fld.4 Shopkeeper attempts to inject unauthorized role/security field on shop -> DENY', true);
  } catch (e) {
    reportTest('Fld.4 Shopkeeper attempts to inject unauthorized role/security field on shop -> DENY', false);
  }

  // Fld.5: Shopkeeper attempts mixed update (allowed openTime + forbidden role) on shop -> DENY (atomicity)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      openTime: '10:00',
      role: 'admin',
    }));
    reportTest('Fld.5 Shopkeeper attempts mixed update (allowed openTime + forbidden role) on shop -> DENY (atomicity)', true);
  } catch (e) {
    reportTest('Fld.5 Shopkeeper attempts mixed update (allowed openTime + forbidden role) on shop -> DENY (atomicity)', false);
  }

  // Fld.6: Admin attempts to mutate createdAt or shopId on shop -> DENY
  try {
    await assertFails(adminDb.collection('shops').doc('shop_a').update({
      createdAt: new Date('2020-01-01T00:00:00Z'),
    }));
    await assertFails(adminDb.collection('shops').doc('shop_a').update({
      shopId: 'shop_renamed',
    }));
    reportTest('Fld.6 Admin attempts to mutate createdAt or shopId on shop -> DENY', true);
  } catch (e) {
    reportTest('Fld.6 Admin attempts to mutate createdAt or shopId on shop -> DENY', false);
  }

  // ── 2. Categories Field Restrictions (Fld.7 - Fld.9) ──
  // Fld.7: Shopkeeper updates allowed fields on category -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_a_fld').update({
      name: 'Updated Category Name',
      sortOrder: 2,
    }));
    reportTest('Fld.7 Shopkeeper updates allowed fields on category -> ALLOW', true);
  } catch (e) {
    reportTest('Fld.7 Shopkeeper updates allowed fields on category -> ALLOW', false);
  }

  // Fld.8: Shopkeeper attempts to mutate category shopId to foreign shop -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_a_fld').update({
      shopId: 'shop_b',
    }));
    reportTest('Fld.8 Shopkeeper attempts to mutate category shopId to foreign shop -> DENY', true);
  } catch (e) {
    reportTest('Fld.8 Shopkeeper attempts to mutate category shopId to foreign shop -> DENY', false);
  }

  // Fld.9: Shopkeeper attempts mixed update on category (allowed name + forbidden shopId) -> DENY (atomicity)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_a_fld').update({
      name: 'Another Name',
      shopId: 'shop_b',
    }));
    reportTest('Fld.9 Shopkeeper attempts mixed update on category (allowed name + forbidden shopId) -> DENY (atomicity)', true);
  } catch (e) {
    reportTest('Fld.9 Shopkeeper attempts mixed update on category (allowed name + forbidden shopId) -> DENY (atomicity)', false);
  }

  // ── 3. Menu Items Field Restrictions (Fld.10 - Fld.12) ──
  // Fld.10: Shopkeeper updates allowed catalog fields on menu item (price, availability) -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a_fld').update({
      price: 120,
      isAvailable: false,
    }));
    reportTest('Fld.10 Shopkeeper updates allowed catalog fields on menu item (price, availability) -> ALLOW', true);
  } catch (e) {
    reportTest('Fld.10 Shopkeeper updates allowed catalog fields on menu item (price, availability) -> ALLOW', false);
  }

  // Fld.11: Shopkeeper attempts to mutate menu item shopId to transfer to another shop -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a_fld').update({
      shopId: 'shop_b',
    }));
    reportTest('Fld.11 Shopkeeper attempts to mutate menu item shopId to transfer to another shop -> DENY', true);
  } catch (e) {
    reportTest('Fld.11 Shopkeeper attempts to mutate menu item shopId to transfer to another shop -> DENY', false);
  }

  // Fld.12: Shopkeeper attempts mixed update on menu item (allowed price + forbidden shopId) -> DENY (atomicity)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a_fld').update({
      price: 150,
      shopId: 'shop_b',
    }));
    reportTest('Fld.12 Shopkeeper attempts mixed update on menu item (allowed price + forbidden shopId) -> DENY (atomicity)', true);
  } catch (e) {
    reportTest('Fld.12 Shopkeeper attempts mixed update on menu item (allowed price + forbidden shopId) -> DENY (atomicity)', false);
  }

  // ── 4. Order Field Restrictions: Customer (Fld.13 - Fld.19) ──
  // Fld.13: Customer updates allowed fields on order cancellation -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('orders').doc('order_cust_a_fld_cancel').update({
      status: 'cancelled',
      cancelledAt: new Date(),
    }));
    reportTest('Fld.13 Customer updates allowed fields on order cancellation -> ALLOW', true);
  } catch (e) {
    reportTest('Fld.13 Customer updates allowed fields on order cancellation -> ALLOW', false);
  }

  // Fld.14: Customer attempts to mutate order totalAmount during cancellation -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      totalAmount: 50,
    }));
    reportTest('Fld.14 Customer attempts to mutate order totalAmount during cancellation -> DENY', true);
  } catch (e) {
    reportTest('Fld.14 Customer attempts to mutate order totalAmount during cancellation -> DENY', false);
  }

  // Fld.15: Customer attempts to mutate order items during cancellation -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      items: [],
    }));
    reportTest('Fld.15 Customer attempts to mutate order items during cancellation -> DENY', true);
  } catch (e) {
    reportTest('Fld.15 Customer attempts to mutate order items during cancellation -> DENY', false);
  }

  // Fld.16: Customer attempts to mutate order deliveryCharges during cancellation -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      deliveryCharges: 100,
    }));
    reportTest('Fld.16 Customer attempts to mutate order deliveryCharges during cancellation -> DENY', true);
  } catch (e) {
    reportTest('Fld.16 Customer attempts to mutate order deliveryCharges during cancellation -> DENY', false);
  }

  // Fld.17: Customer attempts to mutate order acceptDeadline during cancellation -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptDeadline: new Date('2026-09-08T18:00:00Z'),
    }));
    reportTest('Fld.17 Customer attempts to mutate order acceptDeadline during cancellation -> DENY', true);
  } catch (e) {
    reportTest('Fld.17 Customer attempts to mutate order acceptDeadline during cancellation -> DENY', false);
  }

  // Fld.18: Customer attempts to mutate order acceptedAt during cancellation -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptedAt: new Date(),
    }));
    reportTest('Fld.18 Customer attempts to mutate order acceptedAt during cancellation -> DENY', true);
  } catch (e) {
    reportTest('Fld.18 Customer attempts to mutate order acceptedAt during cancellation -> DENY', false);
  }

  // Fld.19: Customer attempts mixed update on order (allowed status + forbidden totalAmount) -> DENY (atomicity)
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').update({
      status: 'cancelled',
      totalAmount: 10,
    }));
    reportTest('Fld.19 Customer attempts mixed update on order (allowed status + forbidden totalAmount) -> DENY (atomicity)', true);
  } catch (e) {
    reportTest('Fld.19 Customer attempts mixed update on order (allowed status + forbidden totalAmount) -> DENY (atomicity)', false);
  }

  // ── 5. Order Field Restrictions: Shopkeeper (Fld.20 - Fld.26) ──
  // Fld.20: Shopkeeper updates allowed fulfillment fields on order -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_cust_a_fld_sk').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('Fld.20 Shopkeeper updates allowed fulfillment fields on order -> ALLOW', true);
  } catch (e) {
    reportTest('Fld.20 Shopkeeper updates allowed fulfillment fields on order -> ALLOW', false);
  }

  // Fld.21: Shopkeeper attempts to mutate order totalAmount / financials -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      totalAmount: 999,
    }));
    reportTest('Fld.21 Shopkeeper attempts to mutate order totalAmount / financials -> DENY', true);
  } catch (e) {
    reportTest('Fld.21 Shopkeeper attempts to mutate order totalAmount / financials -> DENY', false);
  }

  // Fld.22: Shopkeeper attempts to mutate order items -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      items: [{ itemId: 'item_tampered', name: 'Fake Item', price: 999, quantity: 5 }],
    }));
    reportTest('Fld.22 Shopkeeper attempts to mutate order items -> DENY', true);
  } catch (e) {
    reportTest('Fld.22 Shopkeeper attempts to mutate order items -> DENY', false);
  }

  // Fld.23: Shopkeeper attempts to mutate order customerId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      customerId: 'customer_b',
    }));
    reportTest('Fld.23 Shopkeeper attempts to mutate order customerId -> DENY', true);
  } catch (e) {
    reportTest('Fld.23 Shopkeeper attempts to mutate order customerId -> DENY', false);
  }

  // Fld.24: Shopkeeper attempts to mutate order acceptDeadline / deliveryDeadline -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptDeadline: new Date('2026-09-08T20:00:00Z'),
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      deliveryDeadline: new Date('2026-09-08T20:00:00Z'),
    }));
    reportTest('Fld.24 Shopkeeper attempts to mutate order acceptDeadline / deliveryDeadline -> DENY', true);
  } catch (e) {
    reportTest('Fld.24 Shopkeeper attempts to mutate order acceptDeadline / deliveryDeadline -> DENY', false);
  }

  // Fld.25: Shopkeeper attempts to mutate order acceptedAt / deliveredAt -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptedAt: new Date(),
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      deliveredAt: new Date(),
    }));
    reportTest('Fld.25 Shopkeeper attempts to mutate order acceptedAt / deliveredAt -> DENY', true);
  } catch (e) {
    reportTest('Fld.25 Shopkeeper attempts to mutate order acceptedAt / deliveredAt -> DENY', false);
  }

  // Fld.26: Shopkeeper attempts mixed update on order (allowed status + forbidden totalAmount) -> DENY (atomicity)
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').update({
      status: 'accepted',
      totalAmount: 999,
    }));
    reportTest('Fld.26 Shopkeeper attempts mixed update on order (allowed status + forbidden totalAmount) -> DENY (atomicity)', true);
  } catch (e) {
    reportTest('Fld.26 Shopkeeper attempts mixed update on order (allowed status + forbidden totalAmount) -> DENY (atomicity)', false);
  }

  // ── 6. Order Field Restrictions: Admin (Fld.27 - Fld.29) ──
  // Fld.27: Admin attempts to mutate order customerId or shopId -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_cust_a_shop_a').update({
      customerId: 'customer_b',
    }));
    await assertFails(adminDb.collection('orders').doc('order_cust_a_shop_a').update({
      shopId: 'shop_b',
    }));
    reportTest('Fld.27 Admin attempts to mutate order customerId or shopId -> DENY', true);
  } catch (e) {
    reportTest('Fld.27 Admin attempts to mutate order customerId or shopId -> DENY', false);
  }

  // Fld.28: Admin attempts to mutate order totalAmount or items -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_cust_a_shop_a').update({
      totalAmount: 1,
    }));
    await assertFails(adminDb.collection('orders').doc('order_cust_a_shop_a').update({
      items: [],
    }));
    reportTest('Fld.28 Admin attempts to mutate order totalAmount or items -> DENY', true);
  } catch (e) {
    reportTest('Fld.28 Admin attempts to mutate order totalAmount or items -> DENY', false);
  }

  // Fld.29: Admin attempts to mutate order createdAt or lifecycle timestamps -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_cust_a_shop_a').update({
      createdAt: new Date('2020-01-01T00:00:00Z'),
    }));
    await assertFails(adminDb.collection('orders').doc('order_cust_a_shop_a').update({
      acceptedAt: new Date(),
    }));
    await assertFails(adminDb.collection('orders').doc('order_cust_a_shop_a').update({
      deliveredAt: new Date(),
    }));
    reportTest('Fld.29 Admin attempts to mutate order createdAt or lifecycle timestamps -> DENY', true);
  } catch (e) {
    reportTest('Fld.29 Admin attempts to mutate order createdAt or lifecycle timestamps -> DENY', false);
  }

  // ── 7. Device Token Field Restrictions (Fld.30 - Fld.37) ──
  // Fld.30: Token owner updates allowed operational fields on deviceToken -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('deviceTokens').doc('token_cust_a_fld').update({
      platform: 'ios',
      updatedAt: new Date(),
    }));
    reportTest('Fld.30 Token owner updates allowed operational fields on deviceToken -> ALLOW', true);
  } catch (e) {
    reportTest('Fld.30 Token owner updates allowed operational fields on deviceToken -> ALLOW', false);
  }

  // Fld.31: Token owner attempts to mutate token -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      token: 'token_hijacked',
    }));
    reportTest('Fld.31 Token owner attempts to mutate token -> DENY', true);
  } catch (e) {
    reportTest('Fld.31 Token owner attempts to mutate token -> DENY', false);
  }

  // Fld.32: Token owner attempts to mutate uid -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      uid: 'customer_b',
    }));
    reportTest('Fld.32 Token owner attempts to mutate uid -> DENY', true);
  } catch (e) {
    reportTest('Fld.32 Token owner attempts to mutate uid -> DENY', false);
  }

  // Fld.33: Token owner attempts to mutate role -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      role: 'admin',
    }));
    reportTest('Fld.33 Token owner attempts to mutate role -> DENY', true);
  } catch (e) {
    reportTest('Fld.33 Token owner attempts to mutate role -> DENY', false);
  }

  // Fld.34: Token owner attempts to mutate shopId -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      shopId: 'shop_a',
    }));
    reportTest('Fld.34 Token owner attempts to mutate shopId -> DENY', true);
  } catch (e) {
    reportTest('Fld.34 Token owner attempts to mutate shopId -> DENY', false);
  }

  // Fld.35: Token owner attempts to mutate phone -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      phone: '+919999999999',
    }));
    reportTest('Fld.35 Token owner attempts to mutate phone -> DENY', true);
  } catch (e) {
    reportTest('Fld.35 Token owner attempts to mutate phone -> DENY', false);
  }

  // Fld.36: Token owner attempts mixed update (allowed platform + forbidden role) -> DENY (atomicity)
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      platform: 'web',
      role: 'admin',
    }));
    reportTest('Fld.36 Token owner attempts mixed update (allowed platform + forbidden role) -> DENY (atomicity)', true);
  } catch (e) {
    reportTest('Fld.36 Token owner attempts mixed update (allowed platform + forbidden role) -> DENY (atomicity)', false);
  }

  // Fld.37: Token owner attempts mixed update (allowed platform + forbidden phone) -> DENY (atomicity)
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      platform: 'web',
      phone: '+919999999999',
    }));
    reportTest('Fld.37 Token owner attempts mixed update (allowed platform + forbidden phone) -> DENY (atomicity)', true);
  } catch (e) {
    reportTest('Fld.37 Token owner attempts mixed update (allowed platform + forbidden phone) -> DENY (atomicity)', false);
  }

  // ── 8. User & Profile Field Restrictions (Fld.38 - Fld.44) ──
  // Fld.38: User updates allowed profile fields -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('profiles').doc('customer_a').update({
      displayName: 'Customer A Updated Name',
      updatedAt: new Date(),
    }));
    reportTest('Fld.38 User updates allowed profile fields -> ALLOW', true);
  } catch (e) {
    reportTest('Fld.38 User updates allowed profile fields -> ALLOW', false);
  }

  // Fld.39: User attempts to mutate profile role -> DENY
  try {
    await assertFails(customerDb.collection('profiles').doc('customer_a').update({
      role: 'admin',
    }));
    reportTest('Fld.39 User attempts to mutate profile role -> DENY', true);
  } catch (e) {
    reportTest('Fld.39 User attempts to mutate profile role -> DENY', false);
  }

  // Fld.40: User attempts to mutate profile shopId -> DENY
  try {
    await assertFails(customerDb.collection('profiles').doc('customer_a').update({
      shopId: 'shop_a',
    }));
    reportTest('Fld.40 User attempts to mutate profile shopId -> DENY', true);
  } catch (e) {
    reportTest('Fld.40 User attempts to mutate profile shopId -> DENY', false);
  }

  // Fld.41: User attempts to mutate profile status -> DENY
  try {
    await assertFails(customerDb.collection('profiles').doc('customer_a').update({
      status: 'deactivated',
    }));
    reportTest('Fld.41 User attempts to mutate profile status -> DENY', true);
  } catch (e) {
    reportTest('Fld.41 User attempts to mutate profile status -> DENY', false);
  }

  // Fld.42: User attempts to mutate profile phone -> DENY
  try {
    await assertFails(customerDb.collection('users').doc('customer_a').update({
      phone: '+918078643910',
    }));
    reportTest('Fld.42 User attempts to mutate profile phone -> DENY', true);
  } catch (e) {
    reportTest('Fld.42 User attempts to mutate profile phone -> DENY', false);
  }

  // Fld.43: User attempts to mutate profile uid -> DENY
  try {
    await assertFails(customerDb.collection('users').doc('customer_a').update({
      uid: 'customer_b',
    }));
    reportTest('Fld.43 User attempts to mutate profile uid -> DENY', true);
  } catch (e) {
    reportTest('Fld.43 User attempts to mutate profile uid -> DENY', false);
  }

  // Fld.44: User attempts mixed update (allowed displayName + forbidden role) -> DENY (atomicity)
  try {
    await assertFails(customerDb.collection('profiles').doc('customer_a').update({
      displayName: 'Legit Name',
      role: 'admin',
    }));
    reportTest('Fld.44 User attempts mixed update (allowed displayName + forbidden role) -> DENY (atomicity)', true);
  } catch (e) {
    reportTest('Fld.44 User attempts mixed update (allowed displayName + forbidden role) -> DENY (atomicity)', false);
  }

  // ── 9. Support Queries, Server-Only & Invariants (Fld.45 - Fld.50) ──
  // Fld.45: Customer attempts to update supportQuery -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_cust_a').update({
      status: 'resolved',
    }));
    reportTest('Fld.45 Customer attempts to update supportQuery -> DENY', true);
  } catch (e) {
    reportTest('Fld.45 Customer attempts to update supportQuery -> DENY', false);
  }

  // Fld.46: Customer attempts to delete supportQuery -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_cust_a').delete());
    reportTest('Fld.46 Customer attempts to delete supportQuery -> DENY', true);
  } catch (e) {
    reportTest('Fld.46 Customer attempts to delete supportQuery -> DENY', false);
  }

  // Fld.47: Client attempts to write to server-only shopStats -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shopStats').doc('shop_a').update({
      revenue: 999999,
    }));
    reportTest('Fld.47 Client attempts to write to server-only shopStats -> DENY', true);
  } catch (e) {
    reportTest('Fld.47 Client attempts to write to server-only shopStats -> DENY', false);
  }

  // Fld.48: Client attempts to write to server-only _authChallenges -> DENY
  try {
    await assertFails(customerDb.collection('_authChallenges').doc('challenge_fld').set({
      fake: true,
    }));
    reportTest('Fld.48 Client attempts to write to server-only _authChallenges -> DENY', true);
  } catch (e) {
    reportTest('Fld.48 Client attempts to write to server-only _authChallenges -> DENY', false);
  }

  // Fld.49: Customer attempts to create order with pre-filled acceptedAt -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_bad_time').set({
      orderId: 'order_cust_bad_time',
      customerId: 'customer_a',
      shopId: 'shop_a',
      status: 'placed',
      totalAmount: 100,
      items: [{ itemId: 'item_1', name: 'Burger', price: 100, quantity: 1 }],
      acceptedAt: new Date(),
    }));
    reportTest('Fld.49 Customer attempts to create order with pre-filled acceptedAt -> DENY', true);
  } catch (e) {
    reportTest('Fld.49 Customer attempts to create order with pre-filled acceptedAt -> DENY', false);
  }

  // Fld.50: Customer attempts to create support query with unauthorized admin fields -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_bad_fields').set({
      id: 'query_bad_fields',
      name: 'Tamper Query',
      query: 'Testing field restriction on supportQueries',
      phone: '+919876543210',
      phoneNumber: '+919876543210',
      customerId: 'customer_a',
      status: 'unread',
      adminNotes: 'Injected admin notes',
    }));
    reportTest('Fld.50 Customer attempts to create support query with unauthorized admin fields -> DENY', true);
  } catch (e) {
    reportTest('Fld.50 Customer attempts to create support query with unauthorized admin fields -> DENY', false);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHECKPOINT 3.5 REMEDIATION: CREATE-TIME FIELD INTEGRITY (Crt.1 - Crt.26)
  // ══════════════════════════════════════════════════════════════════════════
  console.log('\n--- Checkpoint 3.5 Remediation: Create-Time Field Integrity (Crt.1 - Crt.26) ---');

  // ── Shops Create-Time Schema & Tenant Integrity (Crt.1 - Crt.8) ──
  // Crt.1: Admin legitimate shop create -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_admin_crt_1').set({
      id: 'shop_admin_crt_1',
      shopId: 'shop_admin_crt_1',
      name: 'Admin Valid Shop',
      address: 'Gate 2 Outside',
      isActive: true,
      openTime: '08:00',
      closeTime: '23:00',
    }));
    reportTest('Crt.1 Admin legitimate shop create -> ALLOW', true);
  } catch (e) {
    reportTest('Crt.1 Admin legitimate shop create -> ALLOW', false);
  }

  // Crt.2: Admin inject unknown/security field in shop create (ownerUid) -> DENY
  try {
    await assertFails(adminDb.collection('shops').doc('shop_admin_crt_2').set({
      id: 'shop_admin_crt_2',
      shopId: 'shop_admin_crt_2',
      name: 'Tampered Admin Shop',
      ownerUid: 'admin_injected_uid',
      isActive: true,
    }));
    reportTest('Crt.2 Admin inject unknown/security field in shop create (ownerUid) -> DENY', true);
  } catch (e) {
    reportTest('Crt.2 Admin inject unknown/security field in shop create (ownerUid) -> DENY', false);
  }

  // Crt.3: Admin forge protected identity field (id != docId) -> DENY
  try {
    await assertFails(adminDb.collection('shops').doc('shop_admin_crt_3').set({
      id: 'forged_mismatched_shop_id',
      shopId: 'shop_admin_crt_3',
      name: 'Forged ID Shop',
      isActive: true,
    }));
    reportTest('Crt.3 Admin forge protected identity field (id != docId) -> DENY', true);
  } catch (e) {
    reportTest('Crt.3 Admin forge protected identity field (id != docId) -> DENY', false);
  }

  // Crt.4: Admin cross-tenant identity (shopId != docId) -> DENY
  try {
    await assertFails(adminDb.collection('shops').doc('shop_admin_crt_4').set({
      id: 'shop_admin_crt_4',
      shopId: 'foreign_tenant_shop_id',
      name: 'Cross Tenant Shop',
      isActive: true,
    }));
    reportTest('Crt.4 Admin cross-tenant identity (shopId != docId) -> DENY', true);
  } catch (e) {
    reportTest('Crt.4 Admin cross-tenant identity (shopId != docId) -> DENY', false);
  }

  // Crt.5: Admin legitimate fields + one forbidden field (securityFlags) -> DENY (atomic)
  try {
    await assertFails(adminDb.collection('shops').doc('shop_admin_crt_5').set({
      id: 'shop_admin_crt_5',
      shopId: 'shop_admin_crt_5',
      name: 'Mixed Valid Shop',
      address: 'Gate 2 Outside',
      isActive: true,
      securityFlags: { bypass: true },
    }));
    reportTest('Crt.5 Admin legitimate fields + one forbidden field (securityFlags) -> DENY (atomic)', true);
  } catch (e) {
    reportTest('Crt.5 Admin legitimate fields + one forbidden field (securityFlags) -> DENY (atomic)', false);
  }

  // Crt.6: Shopkeeper shop create -> DENY (Admin-only responsibility)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_sk_crt_6').set({
      id: 'shop_sk_crt_6',
      shopId: 'shop_sk_crt_6',
      name: 'Shopkeeper Bootstrapped Shop',
      isActive: true,
    }));
    reportTest('Crt.6 Shopkeeper shop create -> DENY (Admin-only)', true);
  } catch (e) {
    reportTest('Crt.6 Shopkeeper shop create -> DENY (Admin-only)', false);
  }

  // Crt.7: Customer shop create -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_cust_crt_7').set({
      id: 'shop_cust_crt_7',
      name: 'Customer Shop',
      isActive: true,
    }));
    reportTest('Crt.7 Customer shop create -> DENY', true);
  } catch (e) {
    reportTest('Crt.7 Customer shop create -> DENY', false);
  }

  // Crt.8: Anonymous shop create -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_anon_crt_8').set({
      id: 'shop_anon_crt_8',
      name: 'Anon Shop',
      isActive: true,
    }));
    reportTest('Crt.8 Anonymous shop create -> DENY', true);
  } catch (e) {
    reportTest('Crt.8 Anonymous shop create -> DENY', false);
  }

  // ── Categories Create-Time Schema & Tenant Integrity (Crt.9 - Crt.17) ──
  // Crt.9: Admin legitimate category create -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').collection('categories').doc('cat_admin_crt_9').set({
      id: 'cat_admin_crt_9',
      shopId: 'shop_a',
      name: 'Admin Provisioned Category',
      sortOrder: 1,
      isActive: true,
    }));
    reportTest('Crt.9 Admin legitimate category create -> ALLOW', true);
  } catch (e) {
    reportTest('Crt.9 Admin legitimate category create -> ALLOW', false);
  }

  // Crt.10: Shopkeeper own-shop legitimate category create -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_sk_crt_10').set({
      id: 'cat_sk_crt_10',
      shopId: 'shop_a',
      name: 'Momos Specials',
      sortOrder: 2,
      isActive: true,
    }));
    reportTest('Crt.10 Shopkeeper own-shop legitimate category create -> ALLOW', true);
  } catch (e) {
    reportTest('Crt.10 Shopkeeper own-shop legitimate category create -> ALLOW', false);
  }

  // Crt.11: Shopkeeper category create with wrong shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_sk_crt_11').set({
      id: 'cat_sk_crt_11',
      shopId: 'shop_b',
      name: 'Mismatched Shop Category',
    }));
    reportTest('Crt.11 Shopkeeper category create with wrong shopId -> DENY', true);
  } catch (e) {
    reportTest('Crt.11 Shopkeeper category create with wrong shopId -> DENY', false);
  }

  // Crt.12: Shopkeeper category create with injected security field (role) -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_sk_crt_12').set({
      id: 'cat_sk_crt_12',
      shopId: 'shop_a',
      name: 'Privilege Injected Category',
      role: 'admin',
      isActive: true,
    }));
    reportTest('Crt.12 Shopkeeper category create with injected security field (role) -> DENY', true);
  } catch (e) {
    reportTest('Crt.12 Shopkeeper category create with injected security field (role) -> DENY', false);
  }

  // Crt.13: Shopkeeper category create with mismatched id (id != categoryId) -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_sk_crt_13').set({
      id: 'forged_category_id',
      shopId: 'shop_a',
      name: 'Forged ID Category',
      isActive: true,
    }));
    reportTest('Crt.13 Shopkeeper category create with mismatched id -> DENY', true);
  } catch (e) {
    reportTest('Crt.13 Shopkeeper category create with mismatched id -> DENY', false);
  }

  // Crt.14: Shopkeeper cross-shop category creation (Shopkeeper A in Shop B) -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_b').collection('categories').doc('cat_sk_crt_14').set({
      id: 'cat_sk_crt_14',
      shopId: 'shop_b',
      name: 'Cross Shop Infiltration',
    }));
    reportTest('Crt.14 Shopkeeper cross-shop category creation -> DENY', true);
  } catch (e) {
    reportTest('Crt.14 Shopkeeper cross-shop category creation -> DENY', false);
  }

  // Crt.15: Shopkeeper category legitimate fields + one forbidden field (ownerUid) -> DENY (atomic)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_sk_crt_15').set({
      id: 'cat_sk_crt_15',
      shopId: 'shop_a',
      name: 'Valid Name',
      sortOrder: 3,
      isActive: true,
      ownerUid: 'attacker_uid',
    }));
    reportTest('Crt.15 Shopkeeper category legitimate + forbidden field (ownerUid) -> DENY (atomic)', true);
  } catch (e) {
    reportTest('Crt.15 Shopkeeper category legitimate + forbidden field (ownerUid) -> DENY (atomic)', false);
  }

  // Crt.16: Customer category create -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').collection('categories').doc('cat_cust_crt_16').set({
      id: 'cat_cust_crt_16',
      shopId: 'shop_a',
      name: 'Customer Injected Cat',
    }));
    reportTest('Crt.16 Customer category create -> DENY', true);
  } catch (e) {
    reportTest('Crt.16 Customer category create -> DENY', false);
  }

  // Crt.17: Anonymous category create -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_a').collection('categories').doc('cat_anon_crt_17').set({
      id: 'cat_anon_crt_17',
      shopId: 'shop_a',
      name: 'Anon Injected Cat',
    }));
    reportTest('Crt.17 Anonymous category create -> DENY', true);
  } catch (e) {
    reportTest('Crt.17 Anonymous category create -> DENY', false);
  }

  // ── Menu Items Create-Time Schema & Tenant Integrity (Crt.18 - Crt.26) ──
  // Crt.18: Admin legitimate menu item create -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_admin_crt_18').set({
      id: 'item_admin_crt_18',
      shopId: 'shop_a',
      name: 'Admin Combo Meal',
      details: 'Full loaded meal',
      price: 180,
      categoryId: 'cat_a1',
      isVeg: true,
      isAvailable: true,
      isRecommended: true,
      sortOrder: 1,
    }));
    reportTest('Crt.18 Admin legitimate menu item create -> ALLOW', true);
  } catch (e) {
    reportTest('Crt.18 Admin legitimate menu item create -> ALLOW', false);
  }

  // Crt.19: Shopkeeper own-shop legitimate menu item create -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_sk_crt_19').set({
      id: 'item_sk_crt_19',
      shopId: 'shop_a',
      name: 'Steamed Momos Special',
      details: '8 pcs with dip',
      price: 80,
      categoryId: 'cat_a1',
      isVeg: true,
      isAvailable: true,
      sortOrder: 2,
    }));
    reportTest('Crt.19 Shopkeeper own-shop legitimate menu item create -> ALLOW', true);
  } catch (e) {
    reportTest('Crt.19 Shopkeeper own-shop legitimate menu item create -> ALLOW', false);
  }

  // Crt.20: Shopkeeper menu item create with wrong shopId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_sk_crt_20').set({
      id: 'item_sk_crt_20',
      shopId: 'shop_b',
      name: 'Wrong Tenant Item',
      price: 50,
    }));
    reportTest('Crt.20 Shopkeeper menu item create with wrong shopId -> DENY', true);
  } catch (e) {
    reportTest('Crt.20 Shopkeeper menu item create with wrong shopId -> DENY', false);
  }

  // Crt.21: Shopkeeper menu item create with injected security field (isSuperAdmin) -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_sk_crt_21').set({
      id: 'item_sk_crt_21',
      shopId: 'shop_a',
      name: 'Privileged Item',
      price: 50,
      isSuperAdmin: true,
    }));
    reportTest('Crt.21 Shopkeeper menu item create with injected security field (isSuperAdmin) -> DENY', true);
  } catch (e) {
    reportTest('Crt.21 Shopkeeper menu item create with injected security field (isSuperAdmin) -> DENY', false);
  }

  // Crt.22: Shopkeeper menu item create with mismatched id (id != menuItemId) -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_sk_crt_22').set({
      id: 'forged_item_doc_id',
      shopId: 'shop_a',
      name: 'Forged Item ID',
      price: 50,
    }));
    reportTest('Crt.22 Shopkeeper menu item create with mismatched id -> DENY', true);
  } catch (e) {
    reportTest('Crt.22 Shopkeeper menu item create with mismatched id -> DENY', false);
  }

  // Crt.23: Shopkeeper cross-shop menu item creation (Shopkeeper A in Shop B) -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_b').collection('menuItems').doc('item_sk_crt_23').set({
      id: 'item_sk_crt_23',
      shopId: 'shop_b',
      name: 'Cross Shop Menu Hack',
      price: 50,
    }));
    reportTest('Crt.23 Shopkeeper cross-shop menu item creation -> DENY', true);
  } catch (e) {
    reportTest('Crt.23 Shopkeeper cross-shop menu item creation -> DENY', false);
  }

  // Crt.24: Shopkeeper menu item legitimate fields + one forbidden field (internalRole) -> DENY (atomic)
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_sk_crt_24').set({
      id: 'item_sk_crt_24',
      shopId: 'shop_a',
      name: 'Mixed Valid Item',
      price: 60,
      isAvailable: true,
      internalRole: 'manager',
    }));
    reportTest('Crt.24 Shopkeeper menu item legitimate + forbidden field (internalRole) -> DENY (atomic)', true);
  } catch (e) {
    reportTest('Crt.24 Shopkeeper menu item legitimate + forbidden field (internalRole) -> DENY (atomic)', false);
  }

  // Crt.25: Customer menu item create -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_cust_crt_25').set({
      id: 'item_cust_crt_25',
      shopId: 'shop_a',
      name: 'Customer Injected Food',
      price: 5,
    }));
    reportTest('Crt.25 Customer menu item create -> DENY', true);
  } catch (e) {
    reportTest('Crt.25 Customer menu item create -> DENY', false);
  }

  // Crt.26: Anonymous menu item create -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_a').collection('menuItems').doc('item_anon_crt_26').set({
      id: 'item_anon_crt_26',
      shopId: 'shop_a',
      name: 'Anon Injected Food',
      price: 5,
    }));
    reportTest('Crt.26 Anonymous menu item create -> DENY', true);
  } catch (e) {
    reportTest('Crt.26 Anonymous menu item create -> DENY', false);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHECKPOINT 3.6: RULES TESTING & SECURITY REGRESSION GATE (Gate.1 - Gate.50)
  // ══════════════════════════════════════════════════════════════════════════
  console.log('\n--- Checkpoint 3.6: Rules Testing & Security Regression Gate (Gate.1 - Gate.50) ---');

  // ── 1. Universal Default-Deny Fallthrough (Gate.1 - Gate.12) ──
  // Gate.1: Anonymous read unknown collection -> DENY
  try {
    await assertFails(unauthDb.collection('unknownCollection').doc('doc1').get());
    reportTest('Gate.1 Anonymous read unknown collection -> DENY', true);
  } catch (e) {
    reportTest('Gate.1 Anonymous read unknown collection -> DENY', false);
  }

  // Gate.2: Anonymous write unknown collection -> DENY
  try {
    await assertFails(unauthDb.collection('unknownCollection').doc('doc1').set({ foo: 'bar' }));
    reportTest('Gate.2 Anonymous write unknown collection -> DENY', true);
  } catch (e) {
    reportTest('Gate.2 Anonymous write unknown collection -> DENY', false);
  }

  // Gate.3: Customer read unknown collection -> DENY
  try {
    await assertFails(customerDb.collection('unknownCollection').doc('doc1').get());
    reportTest('Gate.3 Customer read unknown collection -> DENY', true);
  } catch (e) {
    reportTest('Gate.3 Customer read unknown collection -> DENY', false);
  }

  // Gate.4: Customer write unknown collection -> DENY
  try {
    await assertFails(customerDb.collection('unknownCollection').doc('doc1').set({ foo: 'bar' }));
    reportTest('Gate.4 Customer write unknown collection -> DENY', true);
  } catch (e) {
    reportTest('Gate.4 Customer write unknown collection -> DENY', false);
  }

  // Gate.5: Shopkeeper read unknown collection -> DENY
  try {
    await assertFails(shopkeeperADb.collection('unknownCollection').doc('doc1').get());
    reportTest('Gate.5 Shopkeeper read unknown collection -> DENY', true);
  } catch (e) {
    reportTest('Gate.5 Shopkeeper read unknown collection -> DENY', false);
  }

  // Gate.6: Shopkeeper write unknown collection -> DENY
  try {
    await assertFails(shopkeeperADb.collection('unknownCollection').doc('doc1').set({ foo: 'bar' }));
    reportTest('Gate.6 Shopkeeper write unknown collection -> DENY', true);
  } catch (e) {
    reportTest('Gate.6 Shopkeeper write unknown collection -> DENY', false);
  }

  // Gate.7: Admin read unknown collection -> DENY
  try {
    await assertFails(adminDb.collection('unknownCollection').doc('doc1').get());
    reportTest('Gate.7 Admin read unknown collection -> DENY', true);
  } catch (e) {
    reportTest('Gate.7 Admin read unknown collection -> DENY', false);
  }

  // Gate.8: Admin write unknown collection -> DENY
  try {
    await assertFails(adminDb.collection('unknownCollection').doc('doc1').set({ foo: 'bar' }));
    reportTest('Gate.8 Admin write unknown collection -> DENY', true);
  } catch (e) {
    reportTest('Gate.8 Admin write unknown collection -> DENY', false);
  }

  // Gate.9: Anonymous access random nested path -> DENY
  try {
    await assertFails(unauthDb.collection('randomNested').doc('parent').collection('child').doc('doc1').get());
    reportTest('Gate.9 Anonymous access random nested path -> DENY', true);
  } catch (e) {
    reportTest('Gate.9 Anonymous access random nested path -> DENY', false);
  }

  // Gate.10: Customer access random nested path -> DENY
  try {
    await assertFails(customerDb.collection('randomNested').doc('parent').collection('child').doc('doc1').set({ x: 1 }));
    reportTest('Gate.10 Customer access random nested path -> DENY', true);
  } catch (e) {
    reportTest('Gate.10 Customer access random nested path -> DENY', false);
  }

  // Gate.11: Shopkeeper access random nested path -> DENY
  try {
    await assertFails(shopkeeperADb.collection('randomNested').doc('parent').collection('child').doc('doc1').get());
    reportTest('Gate.11 Shopkeeper access random nested path -> DENY', true);
  } catch (e) {
    reportTest('Gate.11 Shopkeeper access random nested path -> DENY', false);
  }

  // Gate.12: Admin access random nested path -> DENY
  try {
    await assertFails(adminDb.collection('randomNested').doc('parent').collection('child').doc('doc1').set({ x: 1 }));
    reportTest('Gate.12 Admin access random nested path -> DENY', true);
  } catch (e) {
    reportTest('Gate.12 Admin access random nested path -> DENY', false);
  }

  // ── 2. Query Safety Matrix (Rules are not filters) (Gate.13 - Gate.26) ──
  // Gate.13: Customer A query own orders -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('orders').where('customerId', '==', 'customer_a').get());
    reportTest('Gate.13 Customer A query own orders -> ALLOW', true);
  } catch (e) {
    reportTest('Gate.13 Customer A query own orders -> ALLOW', false);
  }

  // Gate.14: Customer A unfiltered orders query -> DENY
  try {
    await assertFails(customerDb.collection('orders').get());
    reportTest('Gate.14 Customer A unfiltered orders query -> DENY', true);
  } catch (e) {
    reportTest('Gate.14 Customer A unfiltered orders query -> DENY', false);
  }

  // Gate.15: Customer A cross-customer orders query -> DENY
  try {
    await assertFails(customerDb.collection('orders').where('customerId', '==', 'customer_b').get());
    reportTest('Gate.15 Customer A cross-customer orders query -> DENY', true);
  } catch (e) {
    reportTest('Gate.15 Customer A cross-customer orders query -> DENY', false);
  }

  // Gate.16: Shopkeeper A query own-shop orders -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').where('shopId', '==', 'shop_a').get());
    reportTest('Gate.16 Shopkeeper A query own-shop orders -> ALLOW', true);
  } catch (e) {
    reportTest('Gate.16 Shopkeeper A query own-shop orders -> ALLOW', false);
  }

  // Gate.17: Shopkeeper A unfiltered orders query -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').get());
    reportTest('Gate.17 Shopkeeper A unfiltered orders query -> DENY', true);
  } catch (e) {
    reportTest('Gate.17 Shopkeeper A unfiltered orders query -> DENY', false);
  }

  // Gate.18: Shopkeeper A cross-shop orders query -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').where('shopId', '==', 'shop_b').get());
    reportTest('Gate.18 Shopkeeper A cross-shop orders query -> DENY', true);
  } catch (e) {
    reportTest('Gate.18 Shopkeeper A cross-shop orders query -> DENY', false);
  }

  // Gate.19: Customer A unfiltered supportQueries query -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').get());
    reportTest('Gate.19 Customer A unfiltered supportQueries query -> DENY', true);
  } catch (e) {
    reportTest('Gate.19 Customer A unfiltered supportQueries query -> DENY', false);
  }

  // Gate.20: Customer A foreign-customer supportQueries query -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').where('customerId', '==', 'customer_b').get());
    reportTest('Gate.20 Customer A foreign-customer supportQueries query -> DENY', true);
  } catch (e) {
    reportTest('Gate.20 Customer A foreign-customer supportQueries query -> DENY', false);
  }

  // Gate.21: Shopkeeper query on supportQueries -> DENY
  try {
    await assertFails(shopkeeperADb.collection('supportQueries').get());
    reportTest('Gate.21 Shopkeeper query on supportQueries -> DENY', true);
  } catch (e) {
    reportTest('Gate.21 Shopkeeper query on supportQueries -> DENY', false);
  }

  // Gate.22: Admin query on supportQueries -> ALLOW (platform administration)
  try {
    await assertSucceeds(adminDb.collection('supportQueries').get());
    reportTest('Gate.22 Admin query on supportQueries -> ALLOW', true);
  } catch (e) {
    reportTest('Gate.22 Admin query on supportQueries -> ALLOW', false);
  }

  // Gate.23: Customer A unfiltered deviceTokens query -> DENY (global enumeration protection)
  try {
    await assertFails(customerDb.collection('deviceTokens').get());
    reportTest('Gate.23 Customer A unfiltered deviceTokens query -> DENY', true);
  } catch (e) {
    reportTest('Gate.23 Customer A unfiltered deviceTokens query -> DENY', false);
  }

  // Gate.24: Customer A cross-customer deviceTokens query -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').where('uid', '==', 'customer_b').get());
    reportTest('Gate.24 Customer A cross-customer deviceTokens query -> DENY', true);
  } catch (e) {
    reportTest('Gate.24 Customer A cross-customer deviceTokens query -> DENY', false);
  }

  // Gate.25: Shopkeeper A unfiltered shopStats query -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shopStats').get());
    reportTest('Gate.25 Shopkeeper A unfiltered shopStats query -> DENY', true);
  } catch (e) {
    reportTest('Gate.25 Shopkeeper A unfiltered shopStats query -> DENY', false);
  }

  // Gate.26: Admin query on deviceTokens -> ALLOW (platform audit)
  try {
    await assertSucceeds(adminDb.collection('deviceTokens').get());
    reportTest('Gate.26 Admin query on deviceTokens -> ALLOW', true);
  } catch (e) {
    reportTest('Gate.26 Admin query on deviceTokens -> ALLOW', false);
  }

  // ── 3. Server-Only Collections Complete Regression (Gate.27 - Gate.38) ──
  // Gate.27: Anonymous read server-only _authChallenges -> DENY
  try {
    await assertFails(unauthDb.collection('_authChallenges').doc('challenge_1').get());
    reportTest('Gate.27 Anonymous read server-only _authChallenges -> DENY', true);
  } catch (e) {
    reportTest('Gate.27 Anonymous read server-only _authChallenges -> DENY', false);
  }

  // Gate.28: Customer query server-only _authChallenges -> DENY
  try {
    await assertFails(customerDb.collection('_authChallenges').get());
    reportTest('Gate.28 Customer query server-only _authChallenges -> DENY', true);
  } catch (e) {
    reportTest('Gate.28 Customer query server-only _authChallenges -> DENY', false);
  }

  // Gate.29: Shopkeeper write server-only _authChallenges -> DENY
  try {
    await assertFails(shopkeeperADb.collection('_authChallenges').doc('hack_chal').set({ otp: '123456' }));
    reportTest('Gate.29 Shopkeeper write server-only _authChallenges -> DENY', true);
  } catch (e) {
    reportTest('Gate.29 Shopkeeper write server-only _authChallenges -> DENY', false);
  }

  // Gate.30: Admin write server-only _authChallenges -> DENY (Client SDK blocked)
  try {
    await assertFails(adminDb.collection('_authChallenges').doc('admin_chal').set({ otp: '123456' }));
    reportTest('Gate.30 Admin write server-only _authChallenges -> DENY', true);
  } catch (e) {
    reportTest('Gate.30 Admin write server-only _authChallenges -> DENY', false);
  }

  // Gate.31: Anonymous read server-only auditLogs -> DENY
  try {
    await assertFails(unauthDb.collection('auditLogs').doc('audit_1').get());
    reportTest('Gate.31 Anonymous read server-only auditLogs -> DENY', true);
  } catch (e) {
    reportTest('Gate.31 Anonymous read server-only auditLogs -> DENY', false);
  }

  // Gate.32: Customer query server-only auditLogs -> DENY
  try {
    await assertFails(customerDb.collection('auditLogs').get());
    reportTest('Gate.32 Customer query server-only auditLogs -> DENY', true);
  } catch (e) {
    reportTest('Gate.32 Customer query server-only auditLogs -> DENY', false);
  }

  // Gate.33: Shopkeeper write server-only auditLogs -> DENY
  try {
    await assertFails(shopkeeperADb.collection('auditLogs').doc('hack_log').set({ event: 'tamper' }));
    reportTest('Gate.33 Shopkeeper write server-only auditLogs -> DENY', true);
  } catch (e) {
    reportTest('Gate.33 Shopkeeper write server-only auditLogs -> DENY', false);
  }

  // Gate.34: Admin write server-only auditLogs -> DENY (Client SDK blocked)
  try {
    await assertFails(adminDb.collection('auditLogs').doc('admin_log').set({ event: 'manual' }));
    reportTest('Gate.34 Admin write server-only auditLogs -> DENY', true);
  } catch (e) {
    reportTest('Gate.34 Admin write server-only auditLogs -> DENY', false);
  }

  // Gate.35: Customer read server-only internal_metrics -> DENY
  try {
    await assertFails(customerDb.collection('internal_metrics').doc('metric_1').get());
    reportTest('Gate.35 Customer read server-only internal_metrics -> DENY', true);
  } catch (e) {
    reportTest('Gate.35 Customer read server-only internal_metrics -> DENY', false);
  }

  // Gate.36: Admin write server-only internal_metrics -> DENY (Client SDK blocked)
  try {
    await assertFails(adminDb.collection('internal_metrics').doc('metric_hack').set({ value: 100 }));
    reportTest('Gate.36 Admin write server-only internal_metrics -> DENY', true);
  } catch (e) {
    reportTest('Gate.36 Admin write server-only internal_metrics -> DENY', false);
  }

  // Gate.37: Shopkeeper read server-only adminSettings -> DENY
  try {
    await assertFails(shopkeeperADb.collection('adminSettings').doc('system').get());
    reportTest('Gate.37 Shopkeeper read server-only adminSettings -> DENY', true);
  } catch (e) {
    reportTest('Gate.37 Shopkeeper read server-only adminSettings -> DENY', false);
  }

  // Gate.38: Admin write server-only adminSettings -> DENY (Client SDK blocked)
  try {
    await assertFails(adminDb.collection('adminSettings').doc('system').set({ maintenanceMode: true }));
    reportTest('Gate.38 Admin write server-only adminSettings -> DENY', true);
  } catch (e) {
    reportTest('Gate.38 Admin write server-only adminSettings -> DENY', false);
  }

  // ── 4. Cross-Role, Deletion & Atomic Field Edge Cases (Gate.39 - Gate.50) ──
  // Gate.39: Customer attempts to delete own order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_cust_a_shop_a').delete());
    reportTest('Gate.39 Customer attempts to delete own order -> DENY', true);
  } catch (e) {
    reportTest('Gate.39 Customer attempts to delete own order -> DENY', false);
  }

  // Gate.40: Shopkeeper attempts to delete shop order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_cust_a_shop_a').delete());
    reportTest('Gate.40 Shopkeeper attempts to delete shop order -> DENY', true);
  } catch (e) {
    reportTest('Gate.40 Shopkeeper attempts to delete shop order -> DENY', false);
  }

  // Gate.41: Admin attempts to delete order -> DENY (allow delete: if false)
  try {
    await assertFails(adminDb.collection('orders').doc('order_cust_a_shop_a').delete());
    reportTest('Gate.41 Admin attempts to delete order -> DENY', true);
  } catch (e) {
    reportTest('Gate.41 Admin attempts to delete order -> DENY', false);
  }

  // Gate.42: Customer attempts to delete supportQuery -> DENY
  try {
    await assertFails(customerDb.collection('supportQueries').doc('query_cust_a').delete());
    reportTest('Gate.42 Customer attempts to delete supportQuery -> DENY', true);
  } catch (e) {
    reportTest('Gate.42 Customer attempts to delete supportQuery -> DENY', false);
  }

  // Gate.43: Customer attempts to delete profile doc -> DENY
  try {
    await assertFails(customerDb.collection('users').doc('customer_a').delete());
    reportTest('Gate.43 Customer attempts to delete profile doc -> DENY', true);
  } catch (e) {
    reportTest('Gate.43 Customer attempts to delete profile doc -> DENY', false);
  }

  // Gate.44: Admin attempts to delete profile doc -> DENY (allow delete: if false)
  try {
    await assertFails(adminDb.collection('users').doc('customer_a').delete());
    reportTest('Gate.44 Admin attempts to delete profile doc -> DENY', true);
  } catch (e) {
    reportTest('Gate.44 Admin attempts to delete profile doc -> DENY', false);
  }

  // Gate.45: User profile atomic mixed: valid displayName + forbidden role -> DENY
  try {
    await assertFails(customerDb.collection('profiles').doc('customer_a').update({
      displayName: 'New Name',
      role: 'admin',
    }));
    reportTest('Gate.45 User profile atomic mixed: valid displayName + forbidden role -> DENY', true);
  } catch (e) {
    reportTest('Gate.45 User profile atomic mixed: valid displayName + forbidden role -> DENY', false);
  }

  // Gate.46: User profile atomic mixed: valid bio + forbidden phone -> DENY
  try {
    await assertFails(customerDb.collection('profiles').doc('customer_a').update({
      bio: 'New Bio',
      phone: '+919999999999',
    }));
    reportTest('Gate.46 User profile atomic mixed: valid bio + forbidden phone -> DENY', true);
  } catch (e) {
    reportTest('Gate.46 User profile atomic mixed: valid bio + forbidden phone -> DENY', false);
  }

  // Gate.47: Device token atomic mixed: valid platform + forbidden token -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      platform: 'web',
      token: 'hacked_token',
    }));
    reportTest('Gate.47 Device token atomic mixed: valid platform + forbidden token -> DENY', true);
  } catch (e) {
    reportTest('Gate.47 Device token atomic mixed: valid platform + forbidden token -> DENY', false);
  }

  // Gate.48: Device token atomic mixed: valid updatedAt + forbidden role -> DENY
  try {
    await assertFails(customerDb.collection('deviceTokens').doc('token_cust_a').update({
      updatedAt: new Date(),
      role: 'admin',
    }));
    reportTest('Gate.48 Device token atomic mixed: valid updatedAt + forbidden role -> DENY', true);
  } catch (e) {
    reportTest('Gate.48 Device token atomic mixed: valid updatedAt + forbidden role -> DENY', false);
  }

  // Gate.49: Customer attempts to update shop configuration -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').update({
      isOpen: false,
    }));
    reportTest('Gate.49 Customer attempts to update shop configuration -> DENY', true);
  } catch (e) {
    reportTest('Gate.49 Customer attempts to update shop configuration -> DENY', false);
  }

  // Gate.50: Customer attempts to delete category -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').collection('categories').doc('cat_a1').delete());
    reportTest('Gate.50 Customer attempts to delete category -> DENY', true);
  } catch (e) {
    reportTest('Gate.50 Customer attempts to delete category -> DENY', false);
  }

  // ═════════════════════════════════════════════════════════════════════
  // CHECKPOINT 5.1 ORDER STATE MACHINE & TRANSITION INVARIANTS (OSM.1 - OSM.26)
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n--- Phase 5.1: Order State Machine & Transition Invariants (OSM.1 - OSM.26) ---');

  // OSM.1 Valid transition: placed -> accepted by assigned shopkeeper -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_osm_placed_for_accept').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('OSM.1 Valid transition placed -> accepted by assigned shopkeeper -> ALLOW', true);
  } catch (e) {
    reportTest('OSM.1 Valid transition placed -> accepted by assigned shopkeeper -> ALLOW', false);
  }

  // OSM.2 Valid transition: placed -> rejected by assigned shopkeeper -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_osm_placed_for_reject').update({
      status: 'rejected',
      rejectionReason: 'Items out of stock',
      updatedAt: new Date(),
    }));
    reportTest('OSM.2 Valid transition placed -> rejected by assigned shopkeeper -> ALLOW', true);
  } catch (e) {
    reportTest('OSM.2 Valid transition placed -> rejected by assigned shopkeeper -> ALLOW', false);
  }

  // OSM.3 Valid transition: placed -> cancelled by customer owner -> ALLOW
  try {
    await assertSucceeds(customerDb.collection('orders').doc('order_osm_placed_for_cancel').update({
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('OSM.3 Valid transition placed -> cancelled by customer owner -> ALLOW', true);
  } catch (e) {
    reportTest('OSM.3 Valid transition placed -> cancelled by customer owner -> ALLOW', false);
  }

  // OSM.4 Valid transition: accepted -> delivered by assigned shopkeeper -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_osm_accepted_for_deliver').update({
      status: 'delivered',
      deliveryPersonId: 'dp_101',
      deliveryPersonName: 'Delivery Person',
      updatedAt: new Date(),
    }));
    reportTest('OSM.4 Valid transition accepted -> delivered by assigned shopkeeper -> ALLOW', true);
  } catch (e) {
    reportTest('OSM.4 Valid transition accepted -> delivered by assigned shopkeeper -> ALLOW', false);
  }

  // OSM.5 Invalid lifecycle jump: placed -> delivered by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'delivered',
      updatedAt: new Date(),
    }));
    reportTest('OSM.5 Invalid lifecycle jump placed -> delivered by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.5 Invalid lifecycle jump placed -> delivered by shopkeeper -> DENY', false);
  }

  // OSM.6 Invalid lifecycle jump: placed -> delivered by admin -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'delivered',
      updatedAt: new Date(),
    }));
    reportTest('OSM.6 Invalid lifecycle jump placed -> delivered by admin -> DENY', true);
  } catch (e) {
    reportTest('OSM.6 Invalid lifecycle jump placed -> delivered by admin -> DENY', false);
  }

  // OSM.7 Invalid lifecycle jump: placed -> delivered by customer -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'delivered',
      updatedAt: new Date(),
    }));
    reportTest('OSM.7 Invalid lifecycle jump placed -> delivered by customer -> DENY', true);
  } catch (e) {
    reportTest('OSM.7 Invalid lifecycle jump placed -> delivered by customer -> DENY', false);
  }

  // OSM.8 Arbitrary status injection: placed -> "cooking" by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'cooking',
      updatedAt: new Date(),
    }));
    reportTest('OSM.8 Arbitrary status injection placed -> cooking by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.8 Arbitrary status injection placed -> cooking by shopkeeper -> DENY', false);
  }

  // OSM.9 Arbitrary status injection: placed -> "arbitrary_garbage" by admin -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'arbitrary_garbage',
      updatedAt: new Date(),
    }));
    reportTest('OSM.9 Arbitrary status injection placed -> arbitrary_garbage by admin -> DENY', true);
  } catch (e) {
    reportTest('OSM.9 Arbitrary status injection placed -> arbitrary_garbage by admin -> DENY', false);
  }

  // OSM.10 Invalid transition: accepted -> cancelled by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_accepted_for_invalid').update({
      status: 'cancelled',
      updatedAt: new Date(),
    }));
    reportTest('OSM.10 Invalid transition accepted -> cancelled by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.10 Invalid transition accepted -> cancelled by shopkeeper -> DENY', false);
  }

  // OSM.11 Invalid transition: accepted -> cancelled by customer -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_osm_accepted_for_invalid').update({
      status: 'cancelled',
      updatedAt: new Date(),
    }));
    reportTest('OSM.11 Invalid transition accepted -> cancelled by customer -> DENY', true);
  } catch (e) {
    reportTest('OSM.11 Invalid transition accepted -> cancelled by customer -> DENY', false);
  }

  // OSM.12 Terminal immutability: delivered -> accepted by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_terminal_delivered').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('OSM.12 Terminal immutability delivered -> accepted by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.12 Terminal immutability delivered -> accepted by shopkeeper -> DENY', false);
  }

  // OSM.13 Terminal immutability: delivered -> placed by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_terminal_delivered').update({
      status: 'placed',
      updatedAt: new Date(),
    }));
    reportTest('OSM.13 Terminal immutability delivered -> placed by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.13 Terminal immutability delivered -> placed by shopkeeper -> DENY', false);
  }

  // OSM.14 Terminal immutability: delivered -> cancelled by customer -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_osm_terminal_delivered').update({
      status: 'cancelled',
      updatedAt: new Date(),
    }));
    reportTest('OSM.14 Terminal immutability delivered -> cancelled by customer -> DENY', true);
  } catch (e) {
    reportTest('OSM.14 Terminal immutability delivered -> cancelled by customer -> DENY', false);
  }

  // OSM.15 Terminal immutability: rejected -> accepted by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_terminal_rejected').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('OSM.15 Terminal immutability rejected -> accepted by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.15 Terminal immutability rejected -> accepted by shopkeeper -> DENY', false);
  }

  // OSM.16 Terminal immutability: rejected -> placed by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_terminal_rejected').update({
      status: 'placed',
      updatedAt: new Date(),
    }));
    reportTest('OSM.16 Terminal immutability rejected -> placed by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.16 Terminal immutability rejected -> placed by shopkeeper -> DENY', false);
  }

  // OSM.17 Terminal immutability: cancelled -> accepted by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_terminal_cancelled').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('OSM.17 Terminal immutability cancelled -> accepted by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.17 Terminal immutability cancelled -> accepted by shopkeeper -> DENY', false);
  }

  // OSM.18 Terminal immutability: cancelled -> placed by customer -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_osm_terminal_cancelled').update({
      status: 'placed',
      updatedAt: new Date(),
    }));
    reportTest('OSM.18 Terminal immutability cancelled -> placed by customer -> DENY', true);
  } catch (e) {
    reportTest('OSM.18 Terminal immutability cancelled -> placed by customer -> DENY', false);
  }

  // OSM.19 Terminal immutability: delivery_expired -> delivered by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_terminal_expired').update({
      status: 'delivered',
      updatedAt: new Date(),
    }));
    reportTest('OSM.19 Terminal immutability delivery_expired -> delivered by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.19 Terminal immutability delivery_expired -> delivered by shopkeeper -> DENY', false);
  }

  // OSM.20 Terminal immutability: delivery_expired -> accepted by shopkeeper -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_terminal_expired').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('OSM.20 Terminal immutability delivery_expired -> accepted by shopkeeper -> DENY', true);
  } catch (e) {
    reportTest('OSM.20 Terminal immutability delivery_expired -> accepted by shopkeeper -> DENY', false);
  }

  // OSM.21 Role violation: Customer attempts placed -> accepted -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('OSM.21 Role violation Customer attempts placed -> accepted -> DENY', true);
  } catch (e) {
    reportTest('OSM.21 Role violation Customer attempts placed -> accepted -> DENY', false);
  }

  // OSM.22 Role violation: Shopkeeper attempts placed -> cancelled -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'cancelled',
      updatedAt: new Date(),
    }));
    reportTest('OSM.22 Role violation Shopkeeper attempts placed -> cancelled -> DENY', true);
  } catch (e) {
    reportTest('OSM.22 Role violation Shopkeeper attempts placed -> cancelled -> DENY', false);
  }

  // OSM.23 Tenant isolation: Shopkeeper B attempts transition on Shop A order -> DENY
  try {
    await assertFails(shopkeeperBDb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('OSM.23 Tenant isolation Shopkeeper B attempts transition on Shop A order -> DENY', true);
  } catch (e) {
    reportTest('OSM.23 Tenant isolation Shopkeeper B attempts transition on Shop A order -> DENY', false);
  }

  // OSM.24 Customer isolation: Customer B attempts cancellation on Customer A order -> DENY
  try {
    await assertFails(customer2Db.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('OSM.24 Customer isolation Customer B attempts cancellation on Customer A order -> DENY', true);
  } catch (e) {
    reportTest('OSM.24 Customer isolation Customer B attempts cancellation on Customer A order -> DENY', false);
  }

  // OSM.25 Repeated transition / Idempotency: Shopkeeper preserves status: placed -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('orders').doc('order_osm_placed_for_invalid').update({
      status: 'placed',
      updatedAt: new Date(),
    }));
    reportTest('OSM.25 Repeated transition / Idempotency Shopkeeper preserves status: placed -> ALLOW', true);
  } catch (e) {
    reportTest('OSM.25 Repeated transition / Idempotency Shopkeeper preserves status: placed -> ALLOW', false);
  }

  // OSM.26 Direct client deletion on terminal order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_osm_terminal_delivered').delete());
    await assertFails(customerDb.collection('orders').doc('order_osm_terminal_delivered').delete());
    await assertFails(adminDb.collection('orders').doc('order_osm_terminal_delivered').delete());
    reportTest('OSM.26 Direct client deletion on terminal order -> DENY across all roles', true);
  } catch (e) {
    reportTest('OSM.26 Direct client deletion on terminal order -> DENY across all roles', false);
  }

  // ─── PHASE 5.2: ROLE-BASED STATE TRANSITIONS (RBT.1 - RBT.18) ────────────
  console.log('\n--- Phase 5.2: Role-Based State Transitions ---');

  // RBT.1 Customer attempts placed -> rejected on own order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_rbt_placed_cust').update({
      status: 'rejected',
      rejectionReason: 'Customer self reject attempt',
      updatedAt: new Date(),
    }));
    reportTest('RBT.1 Customer attempts placed -> rejected on own order -> DENY', true);
  } catch (e) {
    reportTest('RBT.1 Customer attempts placed -> rejected on own order -> DENY', false);
  }

  // RBT.2 Customer attempts accepted -> delivered on own order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_rbt_accepted_cust').update({
      status: 'delivered',
      updatedAt: new Date(),
    }));
    reportTest('RBT.2 Customer attempts accepted -> delivered on own order -> DENY', true);
  } catch (e) {
    reportTest('RBT.2 Customer attempts accepted -> delivered on own order -> DENY', false);
  }

  // RBT.3 Customer attempts accepted -> rejected on own order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_rbt_accepted_cust').update({
      status: 'rejected',
      rejectionReason: 'Customer post-accept reject',
      updatedAt: new Date(),
    }));
    reportTest('RBT.3 Customer attempts accepted -> rejected on own order -> DENY', true);
  } catch (e) {
    reportTest('RBT.3 Customer attempts accepted -> rejected on own order -> DENY', false);
  }

  // RBT.4 Customer attempts accepted -> delivery_expired on own order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_rbt_accepted_cust').update({
      status: 'delivery_expired',
      updatedAt: new Date(),
    }));
    reportTest('RBT.4 Customer attempts accepted -> delivery_expired on own order -> DENY', true);
  } catch (e) {
    reportTest('RBT.4 Customer attempts accepted -> delivery_expired on own order -> DENY', false);
  }

  // RBT.5 Customer attempts arbitrary status injection placed -> cooking -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_rbt_placed_cust').update({
      status: 'cooking',
      updatedAt: new Date(),
    }));
    reportTest('RBT.5 Customer attempts arbitrary status injection placed -> cooking -> DENY', true);
  } catch (e) {
    reportTest('RBT.5 Customer attempts arbitrary status injection placed -> cooking -> DENY', false);
  }

  // RBT.6 Shopkeeper attempts placed -> cancelled on assigned shop order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_rbt_placed_sk').update({
      status: 'cancelled',
      updatedAt: new Date(),
    }));
    reportTest('RBT.6 Shopkeeper attempts placed -> cancelled on assigned shop order -> DENY', true);
  } catch (e) {
    reportTest('RBT.6 Shopkeeper attempts placed -> cancelled on assigned shop order -> DENY', false);
  }

  // RBT.7 Shopkeeper attempts accepted -> cancelled on assigned shop order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_rbt_accepted_cust').update({
      status: 'cancelled',
      updatedAt: new Date(),
    }));
    reportTest('RBT.7 Shopkeeper attempts accepted -> cancelled on assigned shop order -> DENY', true);
  } catch (e) {
    reportTest('RBT.7 Shopkeeper attempts accepted -> cancelled on assigned shop order -> DENY', false);
  }

  // RBT.8 Shopkeeper attempts arbitrary status injection accepted -> ready -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_rbt_accepted_cust').update({
      status: 'ready',
      updatedAt: new Date(),
    }));
    reportTest('RBT.8 Shopkeeper attempts arbitrary status injection accepted -> ready -> DENY', true);
  } catch (e) {
    reportTest('RBT.8 Shopkeeper attempts arbitrary status injection accepted -> ready -> DENY', false);
  }

  // RBT.9 Cross-shop attack: Shopkeeper B attempts transition on Shop A order -> DENY
  try {
    await assertFails(shopkeeperBDb.collection('orders').doc('order_rbt_placed_sk').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('RBT.9 Cross-shop attack: Shopkeeper B attempts transition on Shop A order -> DENY', true);
  } catch (e) {
    reportTest('RBT.9 Cross-shop attack: Shopkeeper B attempts transition on Shop A order -> DENY', false);
  }

  // RBT.10 Cross-customer attack: Customer B attempts cancellation on Customer A order -> DENY
  try {
    await assertFails(customer2Db.collection('orders').doc('order_rbt_placed_cust').update({
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('RBT.10 Cross-customer attack: Customer B attempts cancellation on Customer A order -> DENY', true);
  } catch (e) {
    reportTest('RBT.10 Cross-customer attack: Customer B attempts cancellation on Customer A order -> DENY', false);
  }

  // RBT.11 Admin operational transition: placed -> accepted -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('orders').doc('order_rbt_placed_admin').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('RBT.11 Admin operational transition: placed -> accepted -> ALLOW', true);
  } catch (e) {
    reportTest('RBT.11 Admin operational transition: placed -> accepted -> ALLOW', false);
  }

  // RBT.12 Admin operational transition: placed -> cancelled -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('orders').doc('order_rbt_placed_sk').update({
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('RBT.12 Admin operational transition: placed -> cancelled -> ALLOW', true);
  } catch (e) {
    reportTest('RBT.12 Admin operational transition: placed -> cancelled -> ALLOW', false);
  }

  // RBT.13 Admin operational transition: accepted -> delivered -> ALLOW
  try {
    await assertSucceeds(adminDb.collection('orders').doc('order_rbt_accepted_admin').update({
      status: 'delivered',
      deliveryPersonId: 'dp_admin_dispatch',
      deliveryPersonName: 'Admin Dispatcher',
      updatedAt: new Date(),
    }));
    reportTest('RBT.13 Admin operational transition: accepted -> delivered -> ALLOW', true);
  } catch (e) {
    reportTest('RBT.13 Admin operational transition: accepted -> delivered -> ALLOW', false);
  }

  // RBT.14 Admin invalid lifecycle jump: placed -> delivered -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_rbt_placed_cust').update({
      status: 'delivered',
      updatedAt: new Date(),
    }));
    reportTest('RBT.14 Admin invalid lifecycle jump: placed -> delivered -> DENY', true);
  } catch (e) {
    reportTest('RBT.14 Admin invalid lifecycle jump: placed -> delivered -> DENY', false);
  }

  // RBT.15 Admin arbitrary status injection: placed -> cooking -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_rbt_placed_cust').update({
      status: 'cooking',
      updatedAt: new Date(),
    }));
    reportTest('RBT.15 Admin arbitrary status injection: placed -> cooking -> DENY', true);
  } catch (e) {
    reportTest('RBT.15 Admin arbitrary status injection: placed -> cooking -> DENY', false);
  }

  // RBT.16 Admin terminal resurrection: delivered -> accepted -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_osm_terminal_delivered').update({
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('RBT.16 Admin terminal resurrection: delivered -> accepted -> DENY', true);
  } catch (e) {
    reportTest('RBT.16 Admin terminal resurrection: delivered -> accepted -> DENY', false);
  }

  // RBT.17 Admin terminal resurrection: cancelled -> placed -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_osm_terminal_cancelled').update({
      status: 'placed',
      updatedAt: new Date(),
    }));
    reportTest('RBT.17 Admin terminal resurrection: cancelled -> placed -> DENY', true);
  } catch (e) {
    reportTest('RBT.17 Admin terminal resurrection: cancelled -> placed -> DENY', false);
  }

  // RBT.18 Admin mutating immutable order ownership (shopId, customerId) -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_rbt_placed_cust').update({
      shopId: 'shop_hacked',
      updatedAt: new Date(),
    }));
    await assertFails(adminDb.collection('orders').doc('order_rbt_placed_cust').update({
      customerId: 'customer_hacked',
      updatedAt: new Date(),
    }));
    reportTest('RBT.18 Admin mutating immutable order ownership (shopId, customerId) -> DENY', true);
  } catch (e) {
    reportTest('RBT.18 Admin mutating immutable order ownership (shopId, customerId) -> DENY', false);
  }

  console.log('\n--- Phase 5.3: Immutable Order Fields & Field-Mutation Invariants (IMF.1 - IMF.27) ---');

  // IMF.1 Customer mutating customerId on placed order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      customerId: 'attacker_uid',
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.1 Customer mutating customerId on placed order -> DENY', true);
  } catch (e) {
    reportTest('IMF.1 Customer mutating customerId on placed order -> DENY', false);
  }

  // IMF.2 Customer mutating shopId on placed order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      shopId: 'shop_b',
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.2 Customer mutating shopId on placed order -> DENY', true);
  } catch (e) {
    reportTest('IMF.2 Customer mutating shopId on placed order -> DENY', false);
  }

  // IMF.3 Customer mutating orderId on placed order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      orderId: 'hacked_order_id',
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.3 Customer mutating orderId on placed order -> DENY', true);
  } catch (e) {
    reportTest('IMF.3 Customer mutating orderId on placed order -> DENY', false);
  }

  // IMF.4 Customer mutating createdAt on placed order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      createdAt: new Date(Date.now() - 3600000),
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.4 Customer mutating createdAt on placed order -> DENY', true);
  } catch (e) {
    reportTest('IMF.4 Customer mutating createdAt on placed order -> DENY', false);
  }

  // IMF.5 Customer mutating totalAmount / grandTotal / subtotal / deliveryCharges -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      totalAmount: 1,
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      grandTotal: 1,
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      subtotal: 0,
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      deliveryCharges: 999,
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.5 Customer mutating financial totals -> DENY', true);
  } catch (e) {
    reportTest('IMF.5 Customer mutating financial totals -> DENY', false);
  }

  // IMF.6 Customer replacing items array on placed order -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      items: [],
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.6 Customer replacing items array -> DENY', true);
  } catch (e) {
    reportTest('IMF.6 Customer replacing items array -> DENY', false);
  }

  // IMF.7 Customer mutating nested item price / menuItemId -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      items: [
        {
          itemId: 'item_1',
          menuItemId: 'item_1',
          name: 'Burger',
          price: 1,
          quantity: 1,
          subtotal: 1,
          selectedOptions: [],
        }
      ],
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.7 Customer mutating nested item price -> DENY', true);
  } catch (e) {
    reportTest('IMF.7 Customer mutating nested item price -> DENY', false);
  }

  // IMF.8 Customer injecting arbitrary financial fields (price, discount) -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      price: 1,
      discount: 100,
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.8 Customer injecting arbitrary financial fields -> DENY', true);
  } catch (e) {
    reportTest('IMF.8 Customer injecting arbitrary financial fields -> DENY', false);
  }

  // IMF.9 Customer mutating historical snapshots (customerName, shopName) -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      customerName: 'Hacked Name',
      shopName: 'Hacked Shop',
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.9 Customer mutating historical snapshots -> DENY', true);
  } catch (e) {
    reportTest('IMF.9 Customer mutating historical snapshots -> DENY', false);
  }

  // IMF.10 Customer mutating orderMethod, specialInstructions, deliveryNote -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      orderMethod: 'whatsapp',
      specialInstructions: 'Tampered note',
      deliveryNote: 'Tampered delivery location',
      status: 'cancelled',
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.10 Customer mutating orderMethod, specialInstructions, deliveryNote -> DENY', true);
  } catch (e) {
    reportTest('IMF.10 Customer mutating orderMethod, specialInstructions, deliveryNote -> DENY', false);
  }

  // IMF.11 Shopkeeper mutating customerId on placed or accepted order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      customerId: 'attacker_uid',
      status: 'accepted',
      updatedAt: new Date(),
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_accepted_sk').update({
      customerId: 'attacker_uid',
      status: 'delivered',
      deliveryPersonId: 'dp_1',
      deliveryPersonName: 'Driver',
      updatedAt: new Date(),
    }));
    reportTest('IMF.11 Shopkeeper mutating customerId -> DENY', true);
  } catch (e) {
    reportTest('IMF.11 Shopkeeper mutating customerId -> DENY', false);
  }

  // IMF.12 Shopkeeper mutating shopId on placed or accepted order -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      shopId: 'shop_b',
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('IMF.12 Shopkeeper mutating shopId -> DENY', true);
  } catch (e) {
    reportTest('IMF.12 Shopkeeper mutating shopId -> DENY', false);
  }

  // IMF.13 Shopkeeper mutating orderId -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      orderId: 'hacked_sk_order_id',
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('IMF.13 Shopkeeper mutating orderId -> DENY', true);
  } catch (e) {
    reportTest('IMF.13 Shopkeeper mutating orderId -> DENY', false);
  }

  // IMF.14 Shopkeeper mutating createdAt -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      createdAt: new Date(Date.now() - 7200000),
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('IMF.14 Shopkeeper mutating createdAt -> DENY', true);
  } catch (e) {
    reportTest('IMF.14 Shopkeeper mutating createdAt -> DENY', false);
  }

  // IMF.15 Shopkeeper mutating financial fields (totalAmount, grandTotal, subtotal, deliveryCharges) -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      totalAmount: 9999,
      status: 'accepted',
      updatedAt: new Date(),
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      grandTotal: 9999,
      status: 'accepted',
      updatedAt: new Date(),
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      subtotal: 9999,
      status: 'accepted',
      updatedAt: new Date(),
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      deliveryCharges: 500,
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('IMF.15 Shopkeeper mutating financial fields -> DENY', true);
  } catch (e) {
    reportTest('IMF.15 Shopkeeper mutating financial fields -> DENY', false);
  }

  // IMF.16 Shopkeeper replacing items or mutating item prices -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      items: [
        {
          itemId: 'item_1',
          menuItemId: 'item_1',
          name: 'Burger',
          price: 999,
          quantity: 1,
          subtotal: 999,
          selectedOptions: [],
        }
      ],
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('IMF.16 Shopkeeper replacing items or mutating item prices -> DENY', true);
  } catch (e) {
    reportTest('IMF.16 Shopkeeper replacing items or mutating item prices -> DENY', false);
  }

  // IMF.17 Shopkeeper mutating historical snapshots (customerName, customerPhone, shopName) -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      customerName: 'Tampered Customer',
      customerPhone: '+910000000000',
      shopName: 'Tampered Shop',
      status: 'accepted',
      updatedAt: new Date(),
    }));
    reportTest('IMF.17 Shopkeeper mutating historical snapshots -> DENY', true);
  } catch (e) {
    reportTest('IMF.17 Shopkeeper mutating historical snapshots -> DENY', false);
  }

  // IMF.18 Admin client mutating customerId or shopId -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      customerId: 'reassigned_customer',
      adminNote: 'Admin intervention',
      updatedAt: new Date(),
    }));
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      shopId: 'reassigned_shop',
      adminNote: 'Admin intervention',
      updatedAt: new Date(),
    }));
    reportTest('IMF.18 Admin client mutating customerId or shopId -> DENY', true);
  } catch (e) {
    reportTest('IMF.18 Admin client mutating customerId or shopId -> DENY', false);
  }

  // IMF.19 Admin client mutating orderId -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      orderId: 'hacked_admin_order_id',
      adminNote: 'Admin intervention',
      updatedAt: new Date(),
    }));
    reportTest('IMF.19 Admin client mutating orderId -> DENY', true);
  } catch (e) {
    reportTest('IMF.19 Admin client mutating orderId -> DENY', false);
  }

  // IMF.20 Admin client mutating createdAt -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      createdAt: new Date(Date.now() - 86400000),
      adminNote: 'Admin intervention',
      updatedAt: new Date(),
    }));
    reportTest('IMF.20 Admin client mutating createdAt -> DENY', true);
  } catch (e) {
    reportTest('IMF.20 Admin client mutating createdAt -> DENY', false);
  }

  // IMF.21 Admin client mutating financial totals -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      totalAmount: 0,
      adminNote: 'Free order override',
      updatedAt: new Date(),
    }));
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      grandTotal: 0,
      adminNote: 'Free order override',
      updatedAt: new Date(),
    }));
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      subtotal: 0,
      adminNote: 'Free order override',
      updatedAt: new Date(),
    }));
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      deliveryCharges: 0,
      adminNote: 'Free delivery override',
      updatedAt: new Date(),
    }));
    reportTest('IMF.21 Admin client mutating financial totals -> DENY', true);
  } catch (e) {
    reportTest('IMF.21 Admin client mutating financial totals -> DENY', false);
  }

  // IMF.22 Admin client replacing items array or mutating item prices -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      items: [],
      adminNote: 'Items cleared by admin',
      updatedAt: new Date(),
    }));
    reportTest('IMF.22 Admin client replacing items array -> DENY', true);
  } catch (e) {
    reportTest('IMF.22 Admin client replacing items array -> DENY', false);
  }

  // IMF.23 Combined attack: Shopkeeper attempts valid status: accepted + malicious grandTotal: 1 -> DENY atomically
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      status: 'accepted',
      grandTotal: 1,
      updatedAt: new Date(),
    }));
    reportTest('IMF.23 Combined attack: status = accepted + grandTotal = 1 -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.23 Combined attack: status = accepted + grandTotal = 1 -> DENY atomically', false);
  }

  // IMF.24 Combined attack: Shopkeeper attempts valid status: delivered + malicious customerId -> DENY atomically
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_accepted_sk').update({
      status: 'delivered',
      customerId: 'attacker_uid',
      deliveryPersonId: 'dp_1',
      deliveryPersonName: 'Driver',
      updatedAt: new Date(),
    }));
    reportTest('IMF.24 Combined attack: status = delivered + customerId = attacker -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.24 Combined attack: status = delivered + customerId = attacker -> DENY atomically', false);
  }

  // IMF.25 Combined attack: Shopkeeper attempts valid status: rejected + malicious shopId -> DENY atomically
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      status: 'rejected',
      shopId: 'shop_b',
      rejectionReason: 'Out of stock',
      updatedAt: new Date(),
    }));
    reportTest('IMF.25 Combined attack: status = rejected + shopId = attackerShop -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.25 Combined attack: status = rejected + shopId = attackerShop -> DENY atomically', false);
  }

  // IMF.26 Combined attack: Customer attempts valid status: cancelled + malicious createdAt -> DENY atomically
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      status: 'cancelled',
      createdAt: new Date(Date.now() - 86400000),
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.26 Combined attack: status = cancelled + createdAt = fakeOldTimestamp -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.26 Combined attack: status = cancelled + createdAt = fakeOldTimestamp -> DENY atomically', false);
  }

  // IMF.27 Combined attack: Customer attempts valid status: cancelled + malicious subtotal: 0 -> DENY atomically
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      status: 'cancelled',
      subtotal: 0,
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.27 Combined attack: status = cancelled + subtotal = 0 -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.27 Combined attack: status = cancelled + subtotal = 0 -> DENY atomically', false);
  }

  // ─── DEADLINE & SERVER LIFECYCLE FIELD DIRECT ATTACKS (PHASE 5.5) ───

  // IMF.28 Customer attempting to modify acceptDeadline -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      acceptDeadline: new Date(Date.now() + 3600000),
      updatedAt: new Date(),
    }));
    reportTest('IMF.28 Customer mutating acceptDeadline -> DENY', true);
  } catch (e) {
    reportTest('IMF.28 Customer mutating acceptDeadline -> DENY', false);
  }

  // IMF.29 Customer attempting to modify deliveryDeadline -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      deliveryDeadline: new Date(Date.now() + 7200000),
      updatedAt: new Date(),
    }));
    reportTest('IMF.29 Customer mutating deliveryDeadline -> DENY', true);
  } catch (e) {
    reportTest('IMF.29 Customer mutating deliveryDeadline -> DENY', false);
  }

  // IMF.30 Customer attempting to modify acceptedAt -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      acceptedAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.30 Customer mutating acceptedAt -> DENY', true);
  } catch (e) {
    reportTest('IMF.30 Customer mutating acceptedAt -> DENY', false);
  }

  // IMF.31 Customer attempting to modify deliveryExpiredAt -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      deliveryExpiredAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.31 Customer mutating deliveryExpiredAt -> DENY', true);
  } catch (e) {
    reportTest('IMF.31 Customer mutating deliveryExpiredAt -> DENY', false);
  }

  // IMF.32 Customer attempting to modify idempotencyKey -> DENY
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      idempotencyKey: 'forged_key_123',
      updatedAt: new Date(),
    }));
    reportTest('IMF.32 Customer mutating idempotencyKey -> DENY', true);
  } catch (e) {
    reportTest('IMF.32 Customer mutating idempotencyKey -> DENY', false);
  }

  // IMF.33 Shopkeeper attempting to modify acceptDeadline -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      acceptDeadline: new Date(Date.now() + 3600000),
      updatedAt: new Date(),
    }));
    reportTest('IMF.33 Shopkeeper mutating acceptDeadline -> DENY', true);
  } catch (e) {
    reportTest('IMF.33 Shopkeeper mutating acceptDeadline -> DENY', false);
  }

  // IMF.34 Shopkeeper attempting to modify rejectDeadline -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      rejectDeadline: new Date(Date.now() + 3600000),
      updatedAt: new Date(),
    }));
    reportTest('IMF.34 Shopkeeper mutating rejectDeadline -> DENY', true);
  } catch (e) {
    reportTest('IMF.34 Shopkeeper mutating rejectDeadline -> DENY', false);
  }

  // IMF.35 Shopkeeper attempting to modify deliveryDeadline -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_accepted_sk').update({
      deliveryDeadline: new Date(Date.now() + 7200000),
      updatedAt: new Date(),
    }));
    reportTest('IMF.35 Shopkeeper mutating deliveryDeadline -> DENY', true);
  } catch (e) {
    reportTest('IMF.35 Shopkeeper mutating deliveryDeadline -> DENY', false);
  }

  // IMF.36 Shopkeeper attempting to modify acceptedAt or deliveredAt -> DENY
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      acceptedAt: new Date(),
      updatedAt: new Date(),
    }));
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_accepted_sk').update({
      deliveredAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.36 Shopkeeper mutating acceptedAt or deliveredAt -> DENY', true);
  } catch (e) {
    reportTest('IMF.36 Shopkeeper mutating acceptedAt or deliveredAt -> DENY', false);
  }

  // IMF.37 Admin client attempting to modify acceptDeadline or deliveryDeadline -> DENY
  try {
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      acceptDeadline: new Date(Date.now() + 3600000),
      adminNote: 'Admin deadline change',
      updatedAt: new Date(),
    }));
    await assertFails(adminDb.collection('orders').doc('order_imf_placed_admin').update({
      deliveryDeadline: new Date(Date.now() + 7200000),
      adminNote: 'Admin delivery deadline change',
      updatedAt: new Date(),
    }));
    reportTest('IMF.37 Admin client mutating acceptDeadline or deliveryDeadline -> DENY', true);
  } catch (e) {
    reportTest('IMF.37 Admin client mutating acceptDeadline or deliveryDeadline -> DENY', false);
  }

  // IMF.38 Compound attack: status = accepted + deliveryDeadline = futureTime -> DENY atomically
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      status: 'accepted',
      deliveryDeadline: new Date(Date.now() + 86400000),
      updatedAt: new Date(),
    }));
    reportTest('IMF.38 Compound attack: status = accepted + deliveryDeadline = futureTime -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.38 Compound attack: status = accepted + deliveryDeadline = futureTime -> DENY atomically', false);
  }

  // IMF.39 Compound attack: status = rejected + acceptDeadline = futureTime -> DENY atomically
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_placed_sk').update({
      status: 'rejected',
      acceptDeadline: new Date(Date.now() + 86400000),
      rejectionReason: 'Forged deadline extension',
      updatedAt: new Date(),
    }));
    reportTest('IMF.39 Compound attack: status = rejected + acceptDeadline = futureTime -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.39 Compound attack: status = rejected + acceptDeadline = futureTime -> DENY atomically', false);
  }

  // IMF.40 Compound attack: status = delivery_expired + deliveryDeadline = futureTime -> DENY atomically
  try {
    await assertFails(shopkeeperADb.collection('orders').doc('order_imf_accepted_sk').update({
      status: 'delivery_expired',
      deliveryDeadline: new Date(Date.now() + 86400000),
      updatedAt: new Date(),
    }));
    reportTest('IMF.40 Compound attack: status = delivery_expired + deliveryDeadline = futureTime -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.40 Compound attack: status = delivery_expired + deliveryDeadline = futureTime -> DENY atomically', false);
  }

  // IMF.41 Compound attack: status = cancelled + acceptedAt = fakeTimestamp -> DENY atomically
  try {
    await assertFails(customerDb.collection('orders').doc('order_imf_placed_cust').update({
      status: 'cancelled',
      acceptedAt: new Date(),
      cancelledAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('IMF.41 Compound attack: status = cancelled + acceptedAt = fakeTimestamp -> DENY atomically', true);
  } catch (e) {
    reportTest('IMF.41 Compound attack: status = cancelled + acceptedAt = fakeTimestamp -> DENY atomically', false);
  }

  // ═════════════════════════════════════════════════════════════════════
  // SECTION 10: CHECKPOINT 6.4 DIRECT FIRESTORE BYPASS & POINTER RE-ACTIVATION TESTS
  // ═════════════════════════════════════════════════════════════════════
  console.log('\n--- Phase 6.4: Direct Firestore Client SDK Image Pointer Bypass Tests (DIP.1 - DIP.16) ---');

  // DIP.1 Authorized shopkeeper direct update shops/{shopId}.bannerUrl -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      bannerUrl: 'shops/shop_a/banner/retired_asset.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.1 Authorized shopkeeper direct update shops/{shopId}.bannerUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.1 Authorized shopkeeper direct update shops/{shopId}.bannerUrl -> DENY', false);
  }

  // DIP.2 Authorized shopkeeper direct update shops/{shopId}.logoUrl -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      logoUrl: 'shops/shop_a/logo/retired_asset.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.2 Authorized shopkeeper direct update shops/{shopId}.logoUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.2 Authorized shopkeeper direct update shops/{shopId}.logoUrl -> DENY', false);
  }

  // DIP.3 Authorized shopkeeper direct update shops/{shopId}.shopLogoImageUrl -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      shopLogoImageUrl: 'shops/shop_a/logo/retired_asset.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.3 Authorized shopkeeper direct update shops/{shopId}.shopLogoImageUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.3 Authorized shopkeeper direct update shops/{shopId}.shopLogoImageUrl -> DENY', false);
  }

  // DIP.4 Authorized shopkeeper direct update shops/{shopId}.imageUrl -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      imageUrl: 'shops/shop_a/banner/retired_asset.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.4 Authorized shopkeeper direct update shops/{shopId}.imageUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.4 Authorized shopkeeper direct update shops/{shopId}.imageUrl -> DENY', false);
  }

  // DIP.5 Authorized shopkeeper direct update shops/{shopId}/menuItems/{itemId}.imageUrl -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_a1').update({
      imageUrl: 'shops/shop_a/menu/retired_item.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.5 Authorized shopkeeper direct update shops/{shopId}/menuItems/{itemId}.imageUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.5 Authorized shopkeeper direct update shops/{shopId}/menuItems/{itemId}.imageUrl -> DENY', false);
  }

  // DIP.6 Authorized shopkeeper direct create menuItem with non-empty imageUrl -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_new_direct').set({
      id: 'item_new_direct',
      shopId: 'shop_a',
      name: 'Direct Item',
      price: 100,
      imageUrl: 'shops/shop_a/menu/direct_img.jpg',
      categoryId: 'cat_a1',
      isVeg: true,
      isAvailable: true,
      isRecommended: false,
      sortOrder: 1,
      optionGroups: [],
      createdAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('DIP.6 Authorized shopkeeper direct create menuItem with non-empty imageUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.6 Authorized shopkeeper direct create menuItem with non-empty imageUrl -> DENY', false);
  }

  // DIP.7 Authorized shopkeeper direct create menuItem with empty imageUrl -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('menuItems').doc('item_new_empty').set({
      id: 'item_new_empty',
      shopId: 'shop_a',
      name: 'Direct Item Empty',
      price: 100,
      imageUrl: '',
      categoryId: 'cat_a1',
      isVeg: true,
      isAvailable: true,
      isRecommended: false,
      sortOrder: 1,
      optionGroups: [],
      createdAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('DIP.7 Authorized shopkeeper direct create menuItem with empty imageUrl -> ALLOW', true);
  } catch (e) {
    reportTest('DIP.7 Authorized shopkeeper direct create menuItem with empty imageUrl -> ALLOW', false);
  }

  // DIP.8 Authorized shopkeeper direct update shops/{shopId}/categories/{categoryId}.imageUrl -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_a1').update({
      imageUrl: 'shops/shop_a/categories/retired_cat.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.8 Authorized shopkeeper direct update shops/{shopId}/categories/{categoryId}.imageUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.8 Authorized shopkeeper direct update shops/{shopId}/categories/{categoryId}.imageUrl -> DENY', false);
  }

  // DIP.9 Authorized shopkeeper direct create category with arbitrary storage imageUrl -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_new_direct').set({
      id: 'cat_new_direct',
      shopId: 'shop_a',
      name: 'Direct Cat',
      sortOrder: 1,
      displayOrder: 1,
      imageUrl: 'shops/shop_a/categories/direct_img.jpg',
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('DIP.9 Authorized shopkeeper direct create category with arbitrary storage imageUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.9 Authorized shopkeeper direct create category with arbitrary storage imageUrl -> DENY', false);
  }

  // DIP.10 Authorized shopkeeper direct create category with fixed default neutral imageUrl -> ALLOW
  try {
    await assertSucceeds(shopkeeperADb.collection('shops').doc('shop_a').collection('categories').doc('cat_new_neutral').set({
      id: 'cat_new_neutral',
      shopId: 'shop_a',
      name: 'Neutral Cat',
      sortOrder: 1,
      displayOrder: 1,
      imageUrl: 'https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=500',
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    }));
    reportTest('DIP.10 Authorized shopkeeper direct create category with fixed default neutral imageUrl -> ALLOW', true);
  } catch (e) {
    reportTest('DIP.10 Authorized shopkeeper direct create category with fixed default neutral imageUrl -> ALLOW', false);
  }

  // DIP.11 Authorized shopkeeper direct write to deletionIntents -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('deletionIntents').doc('intent_attack').set({
      canonicalPath: 'shops/shop_a/banner/x.jpg',
      status: 'ACTIVE',
    }));
    reportTest('DIP.11 Authorized shopkeeper direct write to deletionIntents -> DENY', true);
  } catch (e) {
    reportTest('DIP.11 Authorized shopkeeper direct write to deletionIntents -> DENY', false);
  }

  // DIP.12 Authorized shopkeeper direct read of deletionIntents -> DENY
  try {
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').collection('deletionIntents').doc('intent_attack').get());
    reportTest('DIP.12 Authorized shopkeeper direct read of deletionIntents -> DENY', true);
  } catch (e) {
    reportTest('DIP.12 Authorized shopkeeper direct read of deletionIntents -> DENY', false);
  }

  // DIP.13 Admin client SDK direct update to shops/{shopId}.bannerUrl -> DENY
  try {
    await assertFails(adminDb.collection('shops').doc('shop_a').update({
      bannerUrl: 'shops/shop_a/banner/admin_direct.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.13 Admin client SDK direct update to shops/{shopId}.bannerUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.13 Admin client SDK direct update to shops/{shopId}.bannerUrl -> DENY', false);
  }

  // DIP.14 Customer direct update to shops/{shopId}.bannerUrl -> DENY
  try {
    await assertFails(customerDb.collection('shops').doc('shop_a').update({
      bannerUrl: 'shops/shop_a/banner/cust_direct.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.14 Customer direct update to shops/{shopId}.bannerUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.14 Customer direct update to shops/{shopId}.bannerUrl -> DENY', false);
  }

  // DIP.15 Unauthenticated direct update to shops/{shopId}.bannerUrl -> DENY
  try {
    await assertFails(unauthDb.collection('shops').doc('shop_a').update({
      bannerUrl: 'shops/shop_a/banner/anon_direct.jpg',
      updatedAt: new Date(),
    }));
    reportTest('DIP.15 Unauthenticated direct update to shops/{shopId}.bannerUrl -> DENY', true);
  } catch (e) {
    reportTest('DIP.15 Unauthenticated direct update to shops/{shopId}.bannerUrl -> DENY', false);
  }

  // DIP.16 TEST A: End-to-End Direct SDK Adversarial Attack:
  // Asset X PENDING_DELETION in deletionIntents -> Valid authenticated shopkeeper directly uses Firestore client SDK to write X into bannerUrl -> REJECTED BEFORE X CAN BECOME ACTIVE
  try {
    // Seed PENDING_DELETION into deletionIntents via Admin SDK (bypassing rules for seed)
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('shops').doc('shop_a').collection('deletionIntents').doc('banner_adv_x_jpg').set({
        canonicalPath: 'shops/shop_a/banner/adv_x.jpg',
        status: 'PENDING_DELETION',
        retiredAt: new Date(),
      });
    });

    // Valid shopkeeper session attempts direct Firestore SDK write to set bannerUrl = adv_x.jpg
    await assertFails(shopkeeperADb.collection('shops').doc('shop_a').update({
      bannerUrl: 'shops/shop_a/banner/adv_x.jpg',
      updatedAt: new Date(),
    }));

    // Verify pointer was not changed
    const shopDoc = await adminDb.collection('shops').doc('shop_a').get();
    const currentBanner = shopDoc.data().bannerUrl || '';
    assert.notStrictEqual(currentBanner, 'shops/shop_a/banner/adv_x.jpg');

    reportTest('DIP.16 TEST A: Asset X PENDING_DELETION -> Shopkeeper direct SDK write to bannerUrl -> DENIED by Firestore Rules', true);
  } catch (e) {
    reportTest('DIP.16 TEST A: Asset X PENDING_DELETION -> Shopkeeper direct SDK write to bannerUrl -> DENIED by Firestore Rules', false);
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
