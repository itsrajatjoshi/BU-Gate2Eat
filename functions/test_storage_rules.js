/**
 * YummBU / BU Gate2Eat — Firebase Storage Security Rules Unit Tests
 * 
 * Phase 6.1 & 6.2 — Storage Authentication & Tenant Isolation Test Suite
 * 
 * Tests against live Firebase Storage Emulator using @firebase/rules-unit-testing.
 * Proves that Storage-level authorization enforces:
 *  - Anonymous upload: DENY
 *  - Anonymous overwrite: DENY
 *  - Anonymous delete: DENY
 *  - Anonymous metadata manipulation: DENY
 *  - Anonymous read for catalog assets: ALLOW
 *  - Anonymous read for non-shop paths: DENY (Default-Deny)
 *  - Authenticated customer upload/overwrite/delete: DENY
 *  - Authenticated customer write outside shop: DENY
 *  - Authenticated customer reading catalog assets: ALLOW (Browsing)
 *  - Authenticated user with no role: DENY
 *  - Authenticated user with admin phone (+918078643910): DENY (no phone backdoor)
 *  - Authenticated user with admin:true flag but role!='admin': DENY (no boolean flag bypass)
 *  - Shopkeeper A -> Shop A (Own Shop): Upload, Overwrite, Delete: ALLOW
 *  - Shopkeeper A -> Shop B (Cross Shop): Upload, Overwrite, Delete, Metadata: DENY
 *  - Shopkeeper B -> Shop A (Cross Shop): Upload, Overwrite, Delete: DENY
 *  - Shopkeeper with missing or empty shopId: DENY
 *  - Admin -> Shop A & Shop B (Platform-wide authority): ALLOW
 *  - Metadata spoofing (fake shopId or uploadedBy in customMetadata): DENY
 *  - Path traversal and escape attempts (../): DENY
 *  - Default-deny for unknown/unmapped paths: DENY
 */

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'bugate2eat-storage-test';
const RULES_PATH = path.resolve(__dirname, '../storage.rules');

let testEnv;
let unauthStorage;
let customerStorage;
let customer2Storage;
let userNoRoleStorage;
let phoneAdminStorage;
let flagAdminStorage;
let shopkeeperAStorage;
let shopkeeperBStorage;
let shopkeeperEmptyShopStorage;
let shopkeeperMissingShopStorage;
let adminStorage;

let passCount = 0;
let totalTests = 0;

function reportTest(name, passed, error) {
  totalTests++;
  if (passed) {
    passCount++;
    console.log(`  ✅ [PASS] ${name}`);
  } else {
    console.error(`  ❌ [FAIL] ${name}`);
    if (error) {
      console.error(`     Error: ${error.message || error}`);
    }
  }
}

async function setup() {
  console.log('🔧 Initializing Storage Rules Test Environment...');
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
    },
  });

  unauthStorage = testEnv.unauthenticatedContext().storage();
  customerStorage = testEnv.authenticatedContext('cust_101', {
    role: 'customer',
    phone_number: '+919876543210',
  }).storage();
  customer2Storage = testEnv.authenticatedContext('cust_202', {
    role: 'customer',
    phone_number: '+919876543211',
  }).storage();
  userNoRoleStorage = testEnv.authenticatedContext('user_no_role', {
    phone_number: '+919876543212',
  }).storage();
  phoneAdminStorage = testEnv.authenticatedContext('attacker_phone', {
    role: 'customer',
    phone_number: '+918078643910',
  }).storage();
  flagAdminStorage = testEnv.authenticatedContext('attacker_flag', {
    role: 'customer',
    admin: true,
  }).storage();
  shopkeeperAStorage = testEnv.authenticatedContext('shopkeeper_A_uid', {
    role: 'shopkeeper',
    shopId: 'shop_A',
    phone_number: '+919876543213',
  }).storage();
  shopkeeperBStorage = testEnv.authenticatedContext('shopkeeper_B_uid', {
    role: 'shopkeeper',
    shopId: 'shop_B',
    phone_number: '+919876543214',
  }).storage();
  shopkeeperEmptyShopStorage = testEnv.authenticatedContext('shopkeeper_empty_uid', {
    role: 'shopkeeper',
    shopId: '',
  }).storage();
  shopkeeperMissingShopStorage = testEnv.authenticatedContext('shopkeeper_missing_uid', {
    role: 'shopkeeper',
  }).storage();
  adminStorage = testEnv.authenticatedContext('admin_uid', {
    role: 'admin',
    phone_number: '+918078643910',
  }).storage();

  console.log('✅ Storage Rules Test Environment initialized.\n');
}

async function runTests() {
  console.log('======================================================================');
  console.log('🔒 PHASE 6.1 & 6.2 — FIREBASE STORAGE AUTH & TENANT ISOLATION TESTS');
  console.log('======================================================================\n');

  const dummyImageBytes = Buffer.from([
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
  ]); // Valid JPEG header
  const imageMetadata = { contentType: 'image/jpeg' };
  const textBytes = Buffer.from('malicious script or text payload');
  const textMetadata = { contentType: 'text/plain' };

  // ─── PART 4: PUBLIC READ SCOPE & ANONYMOUS ATTACK AUDIT ─────────────────────
  console.log('─── Part 4: Public Read Scope & Anonymous Attack Audit ───');

  // Attack A: Anonymous upload
  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/banners/banner.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack A: Anonymous upload to shop banners is BLOCKED', true);
  } catch (e) {
    reportTest('Attack A: Anonymous upload to shop banners is BLOCKED', false);
  }

  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/menu/item.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack A: Anonymous upload to shop menu is BLOCKED', true);
  } catch (e) {
    reportTest('Attack A: Anonymous upload to shop menu is BLOCKED', false);
  }

  // Attack B: Anonymous delete
  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/banners/banner.jpg').delete()
    );
    reportTest('Attack B: Anonymous delete of shop asset is BLOCKED', true);
  } catch (e) {
    reportTest('Attack B: Anonymous delete of shop asset is BLOCKED', false);
  }

  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/menu/item.jpg').delete()
    );
    reportTest('Attack B: Anonymous delete of menu item image is BLOCKED', true);
  } catch (e) {
    reportTest('Attack B: Anonymous delete of menu item image is BLOCKED', false);
  }

  // Attack C: Anonymous overwrite
  // First seed a file as Admin
  await assertSucceeds(
    adminStorage.ref('shops/shop_A/banners/seed_banner.jpg').put(dummyImageBytes, imageMetadata)
  );
  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/banners/seed_banner.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack C: Anonymous overwrite of existing file is BLOCKED', true);
  } catch (e) {
    reportTest('Attack C: Anonymous overwrite of existing file is BLOCKED', false);
  }

  // Attack D: Anonymous metadata manipulation
  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/banners/seed_banner.jpg').updateMetadata({
        customMetadata: { hacked: 'true' },
      })
    );
    reportTest('Attack D: Anonymous metadata update is BLOCKED', true);
  } catch (e) {
    reportTest('Attack D: Anonymous metadata update is BLOCKED', false);
  }

  // ── Seed catalog assets for Public Read testing ──
  await assertSucceeds(adminStorage.ref('shops/shop_A/logos/seed_logo.jpg').put(dummyImageBytes, imageMetadata));
  await assertSucceeds(adminStorage.ref('shops/shop_A/menu/seed_menu.jpg').put(dummyImageBytes, imageMetadata));
  await assertSucceeds(adminStorage.ref('shops/shop_A/categories/seed_cat.jpg').put(dummyImageBytes, imageMetadata));
  await assertSucceeds(adminStorage.ref('shops/shop_A/items/seed_item.jpg').put(dummyImageBytes, imageMetadata));

  // PUBLIC READ ALLOW: Explicit catalog folders
  try {
    await assertSucceeds(unauthStorage.ref('shops/shop_A/banners/seed_banner.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read banner (shops/shop_A/banners/...) is ALLOWED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read banner (shops/shop_A/banners/...) is ALLOWED', false, e);
  }

  try {
    await assertSucceeds(unauthStorage.ref('shops/shop_A/logos/seed_logo.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read logo (shops/shop_A/logos/...) is ALLOWED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read logo (shops/shop_A/logos/...) is ALLOWED', false, e);
  }

  try {
    await assertSucceeds(unauthStorage.ref('shops/shop_A/menu/seed_menu.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read menu (shops/shop_A/menu/...) is ALLOWED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read menu (shops/shop_A/menu/...) is ALLOWED', false, e);
  }

  try {
    await assertSucceeds(unauthStorage.ref('shops/shop_A/categories/seed_cat.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read category (shops/shop_A/categories/...) is ALLOWED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read category (shops/shop_A/categories/...) is ALLOWED', false, e);
  }

  try {
    await assertSucceeds(unauthStorage.ref('shops/shop_A/items/seed_item.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read item (shops/shop_A/items/...) is ALLOWED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read item (shops/shop_A/items/...) is ALLOWED', false, e);
  }

  // PUBLIC READ DENY: Non-catalog folders under /shops/{shopId}/
  try {
    await assertFails(unauthStorage.ref('shops/shop_A/internal/secret.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read shops/shop_A/internal/... is DENIED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read shops/shop_A/internal/... is DENIED', false, e);
  }

  try {
    await assertFails(unauthStorage.ref('shops/shop_A/private/secret.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read shops/shop_A/private/... is DENIED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read shops/shop_A/private/... is DENIED', false, e);
  }

  try {
    await assertFails(unauthStorage.ref('shops/shop_A/temp/secret.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read shops/shop_A/temp/... is DENIED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read shops/shop_A/temp/... is DENIED', false, e);
  }

  try {
    await assertFails(unauthStorage.ref('shops/shop_A/exports/secret.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read shops/shop_A/exports/... is DENIED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read shops/shop_A/exports/... is DENIED', false, e);
  }

  try {
    await assertFails(unauthStorage.ref('shops/shop_A/randomFolder/secret.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read shops/shop_A/randomFolder/... is DENIED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read shops/shop_A/randomFolder/... is DENIED', false, e);
  }

  try {
    await assertFails(unauthStorage.ref('shops/shop_A/deeper/random/path/secret.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read deeper path (shops/shop_A/deeper/random/path/...) is DENIED', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read deeper path (shops/shop_A/deeper/random/path/...) is DENIED', false, e);
  }

  // PUBLIC READ DENY: Top-level paths outside shops/
  try {
    await assertFails(unauthStorage.ref('users/profile_101.jpg').getDownloadURL());
    reportTest('Public Read: Anonymous read outside shops/ (users/) is BLOCKED (Default-Deny)', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read outside shops/ (users/) is BLOCKED (Default-Deny)', false);
  }

  try {
    await assertFails(unauthStorage.ref('system/config.json').getDownloadURL());
    reportTest('Public Read: Anonymous read on system/ is BLOCKED (Default-Deny)', true);
  } catch (e) {
    reportTest('Public Read: Anonymous read on system/ is BLOCKED (Default-Deny)', false);
  }

  // ─── PART 7: ADMIN & ROLE SPOOFING ATTACK AUDIT (6.1 Preservation) ───────────
  console.log('\n─── Part 7: Admin & Role Spoofing Attack Audit (6.1) ───');

  // Attacker with admin phone number (+918078643910) but role != 'admin'
  try {
    await assertFails(
      phoneAdminStorage.ref('shops/shop_A/banners/phone_spoof.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Caller with admin phone (+918078643910) cannot upload without custom claim', true);
  } catch (e) {
    reportTest('Caller with admin phone (+918078643910) cannot upload without custom claim', false);
  }

  try {
    await assertFails(
      phoneAdminStorage.ref('shops/shop_A/banners/seed_banner.jpg').delete()
    );
    reportTest('Caller with admin phone (+918078643910) cannot delete without custom claim', true);
  } catch (e) {
    reportTest('Caller with admin phone (+918078643910) cannot delete without custom claim', false);
  }

  // Attacker with client metadata admin:true but role != 'admin'
  try {
    await assertFails(
      flagAdminStorage.ref('shops/shop_A/banners/flag_spoof.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Caller with admin:true flag cannot upload without role==admin claim', true);
  } catch (e) {
    reportTest('Caller with admin:true flag cannot upload without role==admin claim', false);
  }

  // Authenticated user with missing/undefined role claim
  try {
    await assertFails(
      userNoRoleStorage.ref('shops/shop_A/banners/norole.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Caller with missing role claim cannot upload', true);
  } catch (e) {
    reportTest('Caller with missing role claim cannot upload', false);
  }

  try {
    await assertFails(
      userNoRoleStorage.ref('shops/shop_A/banners/seed_banner.jpg').delete()
    );
    reportTest('Caller with missing role claim cannot delete', true);
  } catch (e) {
    reportTest('Caller with missing role claim cannot delete', false);
  }

  // Clean up seed file
  try {
    await adminStorage.ref('shops/shop_A/banners/seed_banner.jpg').delete();
  } catch (_) {}

  // ─── PART 6: SHOPKEEPER OWN-SHOP POSITIVE OPERATIONS (Phase 6.2) ────────────
  console.log('\n─── Part 6: Shopkeeper Own-Shop Positive Operations (6.2) ───');

  // Shopkeeper A uploads to own shop paths
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/banner_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper A can upload banner to own shop (shop_A)', true);
  } catch (e) {
    reportTest('Shopkeeper A can upload banner to own shop (shop_A)', false);
  }

  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/logos/logo_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper A can upload logo to own shop (shop_A)', true);
  } catch (e) {
    reportTest('Shopkeeper A can upload logo to own shop (shop_A)', false);
  }

  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/menu/burger_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper A can upload menu item to own shop (shop_A)', true);
  } catch (e) {
    reportTest('Shopkeeper A can upload menu item to own shop (shop_A)', false);
  }

  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/categories/cat_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper A can upload category image to own shop (shop_A)', true);
  } catch (e) {
    reportTest('Shopkeeper A can upload category image to own shop (shop_A)', false);
  }

  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/items/special_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper A can upload items image to own shop (shop_A)', true);
  } catch (e) {
    reportTest('Shopkeeper A can upload items image to own shop (shop_A)', false);
  }

  // Shopkeeper A overwrites existing asset in own shop
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/banner_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper A can overwrite existing asset in own shop (shop_A)', true);
  } catch (e) {
    reportTest('Shopkeeper A can overwrite existing asset in own shop (shop_A)', false);
  }

  // Direct client deletion by shopkeeper is strictly disabled (mandatory backend reference delegation)
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/banner_A.jpg').delete()
    );
    reportTest('Shopkeeper A direct delete in own shop is DENIED by Storage Rules (mandatory backend delegation)', true);
  } catch (e) {
    reportTest('Shopkeeper A direct delete in own shop is DENIED by Storage Rules (mandatory backend delegation)', false);
  }
  // Admin cleans up seed file
  try { await adminStorage.ref('shops/shop_A/banners/banner_A.jpg').delete(); } catch (_) {}

  // Shopkeeper B legitimate operations in own shop (shop_B)
  try {
    await assertSucceeds(
      shopkeeperBStorage.ref('shops/shop_B/banners/banner_B.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper B can upload banner to own shop (shop_B)', true);
  } catch (e) {
    reportTest('Shopkeeper B can upload banner to own shop (shop_B)', false);
  }

  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_B/banners/banner_B.jpg').delete()
    );
    reportTest('Shopkeeper B direct delete in own shop is DENIED by Storage Rules (mandatory backend delegation)', true);
  } catch (e) {
    reportTest('Shopkeeper B direct delete in own shop is DENIED by Storage Rules (mandatory backend delegation)', false);
  }
  // Admin cleans up seed file
  try { await adminStorage.ref('shops/shop_B/banners/banner_B.jpg').delete(); } catch (_) {}

  // ─── PART 5: SHOPKEEPER CROSS-SHOP ATTACK AUDIT (Phase 6.2 Isolation) ───────
  console.log('\n─── Part 5: Shopkeeper Cross-Shop Attack Audit (6.2 Isolation) ───');

  // Seed Shop B assets for testing cross-shop mutations
  await assertSucceeds(
    shopkeeperBStorage.ref('shops/shop_B/banners/target_banner.jpg').put(dummyImageBytes, imageMetadata)
  );
  await assertSucceeds(
    shopkeeperBStorage.ref('shops/shop_B/menu/target_pizza.jpg').put(dummyImageBytes, imageMetadata)
  );

  // Attack A: Shopkeeper A uploads to Shop B paths
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/banners/malicious.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B banners', true);
  } catch (e) {
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B banners', false);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/logos/malicious.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B logos', true);
  } catch (e) {
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B logos', false);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/menu/malicious.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B menu', true);
  } catch (e) {
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B menu', false);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/categories/malicious.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B categories', true);
  } catch (e) {
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B categories', false);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/items/malicious.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B items', true);
  } catch (e) {
    reportTest('Attack A: Shopkeeper A cannot upload to Shop B items', false);
  }

  // Attack B: Shopkeeper A overwrites Shop B asset
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/banners/target_banner.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Attack B: Shopkeeper A cannot overwrite existing Shop B banner', true);
  } catch (e) {
    reportTest('Attack B: Shopkeeper A cannot overwrite existing Shop B banner', false);
  }

  // Attack C: Shopkeeper A deletes Shop B asset
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/banners/target_banner.jpg').delete()
    );
    reportTest('Attack C: Shopkeeper A cannot delete existing Shop B banner', true);
  } catch (e) {
    reportTest('Attack C: Shopkeeper A cannot delete existing Shop B banner', false);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/menu/target_pizza.jpg').delete()
    );
    reportTest('Attack C: Shopkeeper A cannot delete existing Shop B menu item image', true);
  } catch (e) {
    reportTest('Attack C: Shopkeeper A cannot delete existing Shop B menu item image', false);
  }

  // Attack D: Shopkeeper A updates metadata on Shop B asset
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/banners/target_banner.jpg').updateMetadata({
        customMetadata: { defaced: 'true' },
      })
    );
    reportTest('Attack D: Shopkeeper A cannot update metadata of Shop B asset', true);
  } catch (e) {
    reportTest('Attack D: Shopkeeper A cannot update metadata of Shop B asset', false);
  }

  // Reverse cross-shop: Shopkeeper B attempts to mutate Shop A
  // First seed Shop A asset
  await assertSucceeds(
    shopkeeperAStorage.ref('shops/shop_A/banners/target_banner_A.jpg').put(dummyImageBytes, imageMetadata)
  );

  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/malicious_from_B.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Reverse Attack: Shopkeeper B cannot upload to Shop A banners', true);
  } catch (e) {
    reportTest('Reverse Attack: Shopkeeper B cannot upload to Shop A banners', false);
  }

  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/target_banner_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Reverse Attack: Shopkeeper B cannot overwrite Shop A banner', true);
  } catch (e) {
    reportTest('Reverse Attack: Shopkeeper B cannot overwrite Shop A banner', false);
  }

  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/target_banner_A.jpg').delete()
    );
    reportTest('Reverse Attack: Shopkeeper B cannot delete Shop A banner', true);
  } catch (e) {
    reportTest('Reverse Attack: Shopkeeper B cannot delete Shop A banner', false);
  }

  // Clean up seeded targets
  try { await shopkeeperBStorage.ref('shops/shop_B/banners/target_banner.jpg').delete(); } catch (_) {}
  try { await shopkeeperBStorage.ref('shops/shop_B/menu/target_pizza.jpg').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/banners/target_banner_A.jpg').delete(); } catch (_) {}

  // ─── PART 7: ADMIN CROSS-SHOP ACCESS ────────────────────────────────────────
  console.log('\n─── Part 7: Admin Cross-Shop Access (Platform-wide authority) ───');

  // Admin upload to Shop A and Shop B
  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_A/banners/admin_banner_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Admin can upload to Shop A', true);
  } catch (e) {
    reportTest('Admin can upload to Shop A', false);
  }

  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_B/banners/admin_banner_B.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Admin can upload to Shop B', true);
  } catch (e) {
    reportTest('Admin can upload to Shop B', false);
  }

  // Admin overwrite in Shop A and Shop B
  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_A/banners/admin_banner_A.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Admin can overwrite in Shop A', true);
  } catch (e) {
    reportTest('Admin can overwrite in Shop A', false);
  }

  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_B/banners/admin_banner_B.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Admin can overwrite in Shop B', true);
  } catch (e) {
    reportTest('Admin can overwrite in Shop B', false);
  }

  // Admin delete in Shop A and Shop B
  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_A/banners/admin_banner_A.jpg').delete()
    );
    reportTest('Admin can delete in Shop A', true);
  } catch (e) {
    reportTest('Admin can delete in Shop A', false);
  }

  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_B/banners/admin_banner_B.jpg').delete()
    );
    reportTest('Admin can delete in Shop B', true);
  } catch (e) {
    reportTest('Admin can delete in Shop B', false);
  }

  // ─── PART 8: CUSTOMER MUTATION ISOLATION ────────────────────────────────────
  console.log('\n─── Part 8: Customer Mutation Isolation (All Shops Blocked) ───');

  // Customer upload to Shop A and Shop B
  try {
    await assertFails(
      customerStorage.ref('shops/shop_A/banners/customer_hack.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Customer cannot upload to Shop A', true);
  } catch (e) {
    reportTest('Customer cannot upload to Shop A', false);
  }

  try {
    await assertFails(
      customerStorage.ref('shops/shop_B/banners/customer_hack.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Customer cannot upload to Shop B', true);
  } catch (e) {
    reportTest('Customer cannot upload to Shop B', false);
  }

  // Customer delete in Shop A and Shop B
  try {
    await assertFails(
      customerStorage.ref('shops/shop_A/logos/logo_A.jpg').delete()
    );
    reportTest('Customer cannot delete in Shop A', true);
  } catch (e) {
    reportTest('Customer cannot delete in Shop A', false);
  }

  try {
    await assertFails(
      customerStorage.ref('shops/shop_B/logos/logo_B.jpg').delete()
    );
    reportTest('Customer cannot delete in Shop B', true);
  } catch (e) {
    reportTest('Customer cannot delete in Shop B', false);
  }

  // Customer catalog reading for Shop A and Shop B is permitted
  try {
    await assertSucceeds(
      customerStorage.ref('shops/shop_A/logos/logo_A.jpg').getDownloadURL()
    );
    reportTest('Customer can read catalog image of Shop A (browsing)', true);
  } catch (e) {
    reportTest('Customer can read catalog image of Shop A (browsing)', false);
  }

  // Clean up remaining assets
  try { await shopkeeperAStorage.ref('shops/shop_A/logos/logo_A.jpg').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/menu/burger_A.jpg').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/categories/cat_A.jpg').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/items/special_A.jpg').delete(); } catch (_) {}

  // ─── PART 9 & 11: INVALID OR MISSING SHOPID CLAIMS ──────────────────────────
  console.log('\n─── Part 9 & 11: Invalid or Missing ShopId Claims ───');

  try {
    await assertFails(
      shopkeeperEmptyShopStorage.ref('shops/shop_A/banners/hack.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper with empty string shopId claim is BLOCKED', true);
  } catch (e) {
    reportTest('Shopkeeper with empty string shopId claim is BLOCKED', false);
  }

  try {
    await assertFails(
      shopkeeperMissingShopStorage.ref('shops/shop_A/banners/hack.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Shopkeeper with missing shopId claim is BLOCKED', true);
  } catch (e) {
    reportTest('Shopkeeper with missing shopId claim is BLOCKED', false);
  }

  // ─── PART 12: METADATA SPOOFING ATTACK AUDIT ────────────────────────────────
  console.log('\n─── Part 12: Metadata Spoofing Attack Audit ───');

  // Shopkeeper A attempts to upload to Shop B with customMetadata containing shopId: 'shop_A'
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/banners/spoofed_meta.jpg').put(dummyImageBytes, {
        contentType: 'image/jpeg',
        customMetadata: {
          shopId: 'shop_A',
          uploadedBy: 'shopkeeper_A_uid',
        },
      })
    );
    reportTest('Metadata spoofing: Shopkeeper A supplying own shopId in metadata cannot write to Shop B', true);
  } catch (e) {
    reportTest('Metadata spoofing: Shopkeeper A supplying own shopId in metadata cannot write to Shop B', false);
  }

  // Shopkeeper A attempts to upload to Shop B with customMetadata containing shopId: 'shop_B'
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_B/banners/spoofed_meta2.jpg').put(dummyImageBytes, {
        contentType: 'image/jpeg',
        customMetadata: {
          shopId: 'shop_B',
          uploadedBy: 'shopkeeper_B_uid',
        },
      })
    );
    reportTest('Metadata spoofing: Shopkeeper A claiming target shopId in metadata cannot write to Shop B', true);
  } catch (e) {
    reportTest('Metadata spoofing: Shopkeeper A claiming target shopId in metadata cannot write to Shop B', false);
  }

  // Customer attempts to upload with admin metadata
  try {
    await assertFails(
      customerStorage.ref('shops/shop_A/banners/spoofed_admin.jpg').put(dummyImageBytes, {
        contentType: 'image/jpeg',
        customMetadata: {
          role: 'admin',
          shopId: 'shop_A',
        },
      })
    );
    reportTest('Metadata spoofing: Customer supplying role=admin in metadata cannot upload', true);
  } catch (e) {
    reportTest('Metadata spoofing: Customer supplying role=admin in metadata cannot upload', false);
  }

  // ─── NON-CATALOG FOLDER MUTATION DENY (Shopkeeper & Admin Protection) ─────
  console.log('\n─── Non-Catalog Folder Mutation Deny (Scope Containment) ───');

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/internal/secret.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/internal/... is DENIED', true);
  } catch (e) {
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/internal/... is DENIED', false, e);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/private/secret.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/private/... is DENIED', true);
  } catch (e) {
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/private/... is DENIED', false, e);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/temp/secret.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/temp/... is DENIED', true);
  } catch (e) {
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/temp/... is DENIED', false, e);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/exports/secret.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/exports/... is DENIED', true);
  } catch (e) {
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/exports/... is DENIED', false, e);
  }

  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/randomFolder/secret.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/randomFolder/... is DENIED', true);
  } catch (e) {
    reportTest('Scope Containment: Shopkeeper A upload to shops/shop_A/randomFolder/... is DENIED', false, e);
  }

  // ─── PART 10 & 11: PATH TRAVERSAL & MALFORMED PATH AUDIT ───────────────────
  console.log('\n─── Part 10 & 11: Path Traversal & Malformed Path Audit ───');

  // Traversal A: shops/shop_A/../shop_B/banners/traversal.jpg
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/../shop_B/banners/traversal.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Path Traversal: shops/shop_A/../shop_B/banners/traversal.jpg is BLOCKED', true);
  } catch (e) {
    reportTest('Path Traversal: shops/shop_A/../shop_B/banners/traversal.jpg is BLOCKED', false, e);
  }

  // Traversal B: shops/shop_A/.../shop_B/banners/traversal.jpg
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/.../shop_B/banners/traversal.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Path Traversal: shops/shop_A/.../shop_B/banners/traversal.jpg is BLOCKED', true);
  } catch (e) {
    reportTest('Path Traversal: shops/shop_A/.../shop_B/banners/traversal.jpg is BLOCKED', false, e);
  }

  // Traversal C: Escape to root via ../../
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/../../root_escape.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Path Traversal: Escape to root via shops/shop_A/../../root_escape.jpg is BLOCKED', true);
  } catch (e) {
    reportTest('Path Traversal: Escape to root via shops/shop_A/../../root_escape.jpg is BLOCKED', false, e);
  }

  // Traversal D: shops/../system/secret.txt (Customer)
  try {
    await assertFails(
      customerStorage.ref('shops/../system/secret.txt').put(textBytes, textMetadata)
    );
    reportTest('Path Traversal: Customer shops/../system/secret.txt is BLOCKED', true);
  } catch (e) {
    reportTest('Path Traversal: Customer shops/../system/secret.txt is BLOCKED', false);
  }

  // Traversal E: shops/../system/secret.txt (Anonymous)
  try {
    await assertFails(
      unauthStorage.ref('shops/../system/secret.txt').put(textBytes, textMetadata)
    );
    reportTest('Path Traversal: Anonymous shops/../system/secret.txt is BLOCKED', true);
  } catch (e) {
    reportTest('Path Traversal: Anonymous shops/../system/secret.txt is BLOCKED', false);
  }

  // Malformed F: shops/shop_A/folder/...
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/...').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Malformed Path: Traversal dot fileName "shops/shop_A/banners/..." is BLOCKED', true);
  } catch (e) {
    reportTest('Malformed Path: Traversal dot fileName "shops/shop_A/banners/..." is BLOCKED', false, e);
  }

  // Malformed G: Extra path segments (shops/shop_A/folder/file/extra)
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/file.jpg/extra').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Malformed Path: Extra segment "shops/shop_A/banners/file.jpg/extra" is BLOCKED', true);
  } catch (e) {
    reportTest('Malformed Path: Extra segment "shops/shop_A/banners/file.jpg/extra" is BLOCKED', false, e);
  }

  // Malformed H: Missing shopId segment (shops//banners/file.jpg)
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops//banners/file.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Malformed Path: Empty shopId "shops//banners/file.jpg" is BLOCKED', true);
  } catch (e) {
    reportTest('Malformed Path: Empty shopId "shops//banners/file.jpg" is BLOCKED', false, e);
  }

  // Malformed I: Missing folder segment (shops/shop_A//file.jpg)
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A//file.jpg').put(dummyImageBytes, imageMetadata)
    );
    reportTest('Malformed Path: Empty folder "shops/shop_A//file.jpg" is BLOCKED', true);
  } catch (e) {
    reportTest('Malformed Path: Empty folder "shops/shop_A//file.jpg" is BLOCKED', false, e);
  }

  // ─── PHASE 6.3: FILE VALIDATION (SIZE, CONTENT-TYPE, FILENAME) ──────────────
  console.log('\n─── Phase 6.3: File Size Validation Tests ───');

  const valid500KbBytes = Buffer.alloc(500 * 1024, 0x41); // 500 KB dummy buffer
  const exact1MbBytes = Buffer.alloc(1 * 1024 * 1024, 0x41); // 1,048,576 bytes
  const oversizedBytes = Buffer.alloc(1 * 1024 * 1024 + 1, 0x41); // 1,048,577 bytes (1MB + 1 byte)
  const huge5MbBytes = Buffer.alloc(5 * 1024 * 1024, 0x41); // 5 MB buffer
  const emptyBytes = Buffer.alloc(0); // 0 bytes

  const jpegMeta = { contentType: 'image/jpeg' };
  const pngMeta = { contentType: 'image/png' };
  const webpMeta = { contentType: 'image/webp' };
  const plainTextMeta = { contentType: 'text/plain' };
  const jsonMeta = { contentType: 'application/json' };
  const octetMeta = { contentType: 'application/octet-stream' };
  const jsMeta = { contentType: 'application/javascript' };
  const htmlMeta = { contentType: 'text/html' };

  // Size Test 1: Upload below limit (500 KB) -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/size_500kb.jpg').put(valid500KbBytes, jpegMeta)
    );
    reportTest('File Size: Upload below limit (500 KB <= 1 MB) is ALLOWED', true);
  } catch (e) {
    reportTest('File Size: Upload below limit (500 KB <= 1 MB) is ALLOWED', false, e);
  }

  // Size Test 2: Upload exactly at 1 MB limit (1,048,576 bytes) -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/size_exact_1mb.jpg').put(exact1MbBytes, jpegMeta)
    );
    reportTest('File Size: Upload exactly at 1 MB limit (1,048,576 bytes) is ALLOWED', true);
  } catch (e) {
    reportTest('File Size: Upload exactly at 1 MB limit (1,048,576 bytes) is ALLOWED', false, e);
  }

  // Size Test 3: Upload exceeding limit by 1 byte (1,048,577 bytes) -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/size_oversized.jpg').put(oversizedBytes, jpegMeta)
    );
    reportTest('File Size: Upload exceeding limit by 1 byte (1 MB + 1 byte) is DENIED', true);
  } catch (e) {
    reportTest('File Size: Upload exceeding limit by 1 byte (1 MB + 1 byte) is DENIED', false, e);
  }

  // Size Test 4: Upload empty file (0 bytes) -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/size_empty.jpg').put(emptyBytes, jpegMeta)
    );
    reportTest('File Size: Upload empty file (0 bytes) is DENIED', true);
  } catch (e) {
    reportTest('File Size: Upload empty file (0 bytes) is DENIED', false, e);
  }

  // Size Test 5: Upload large malicious file (5 MB) -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/size_huge.jpg').put(huge5MbBytes, jpegMeta)
    );
    reportTest('File Size: Upload large malicious file (5 MB) is DENIED', true);
  } catch (e) {
    reportTest('File Size: Upload large malicious file (5 MB) is DENIED', false, e);
  }

  console.log('\n─── Phase 6.3: Content-Type Validation Tests ───');

  // Content-Type 1: image/jpeg -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/items/valid_jpeg.jpg').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Content-Type: image/jpeg upload is ALLOWED', true);
  } catch (e) {
    reportTest('Content-Type: image/jpeg upload is ALLOWED', false, e);
  }

  // Content-Type 2: image/png -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/items/valid_png.png').put(dummyImageBytes, pngMeta)
    );
    reportTest('Content-Type: image/png upload is ALLOWED', true);
  } catch (e) {
    reportTest('Content-Type: image/png upload is ALLOWED', false, e);
  }

  // Content-Type 3: image/webp -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/items/valid_webp.webp').put(dummyImageBytes, webpMeta)
    );
    reportTest('Content-Type: image/webp upload is ALLOWED', true);
  } catch (e) {
    reportTest('Content-Type: image/webp upload is ALLOWED', false, e);
  }

  // Content-Type 4: text/plain -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/malicious.jpg').put(dummyImageBytes, plainTextMeta)
    );
    reportTest('Content-Type: text/plain upload is DENIED', true);
  } catch (e) {
    reportTest('Content-Type: text/plain upload is DENIED', false, e);
  }

  // Content-Type 5: application/json -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/data.jpg').put(dummyImageBytes, jsonMeta)
    );
    reportTest('Content-Type: application/json upload is DENIED', true);
  } catch (e) {
    reportTest('Content-Type: application/json upload is DENIED', false, e);
  }

  // Content-Type 6: application/octet-stream -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/binary.jpg').put(dummyImageBytes, octetMeta)
    );
    reportTest('Content-Type: application/octet-stream upload is DENIED', true);
  } catch (e) {
    reportTest('Content-Type: application/octet-stream upload is DENIED', false, e);
  }

  // Content-Type 7: application/javascript -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/script.jpg').put(dummyImageBytes, jsMeta)
    );
    reportTest('Content-Type: application/javascript upload is DENIED', true);
  } catch (e) {
    reportTest('Content-Type: application/javascript upload is DENIED', false, e);
  }

  // Content-Type 8: text/html -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/page.jpg').put(dummyImageBytes, htmlMeta)
    );
    reportTest('Content-Type: text/html upload is DENIED', true);
  } catch (e) {
    reportTest('Content-Type: text/html upload is DENIED', false, e);
  }

  // Content-Type 9: Empty/Missing content type -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/no_type.jpg').put(dummyImageBytes, {})
    );
    reportTest('Content-Type: Missing/empty contentType upload is DENIED', true);
  } catch (e) {
    reportTest('Content-Type: Missing/empty contentType upload is DENIED', false, e);
  }

  console.log('\n─── Phase 6.3: Filename Validation Tests ───');

  // Filename 1: Valid alphanumeric timestamp filename -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/items/1788960743164_burger_combo.jpg').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Filename: Standard generated timestamp filename is ALLOWED', true);
  } catch (e) {
    reportTest('Filename: Standard generated timestamp filename is ALLOWED', false, e);
  }

  // Filename 2: Uppercase extension (JPG, PNG) -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/items/photo_camera.JPG').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Filename: Uppercase image extension (.JPG) is ALLOWED', true);
  } catch (e) {
    reportTest('Filename: Uppercase image extension (.JPG) is ALLOWED', false, e);
  }

  // Filename 3: Executable extension (.exe) -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/exploit.exe').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Filename: Executable extension (.exe) is DENIED', true);
  } catch (e) {
    reportTest('Filename: Executable extension (.exe) is DENIED', false, e);
  }

  // Filename 4: Script extension (.php, .js) -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/shell.php').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Filename: Script extension (.php) is DENIED', true);
  } catch (e) {
    reportTest('Filename: Script extension (.php) is DENIED', false, e);
  }

  // Filename 5: Spaces or control characters in filename -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/my burger photo.jpg').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Filename: Filename with spaces is DENIED', true);
  } catch (e) {
    reportTest('Filename: Filename with spaces is DENIED', false, e);
  }

  // Filename 6: Shell metacharacters ($*) -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/items/hack$name.jpg').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Filename: Filename with metacharacters ($) is DENIED', true);
  } catch (e) {
    reportTest('Filename: Filename with metacharacters ($) is DENIED', false, e);
  }

  // Filename 7: Excessive filename length (> 128 chars) -> DENY
  const longName = 'a'.repeat(130) + '.jpg';
  try {
    await assertFails(
      shopkeeperAStorage.ref(`shops/shop_A/items/${longName}`).put(dummyImageBytes, jpegMeta)
    );
    reportTest('Filename: Excessive filename length (> 128 chars) is DENIED', true);
  } catch (e) {
    reportTest('Filename: Excessive filename length (> 128 chars) is DENIED', false, e);
  }

  console.log('\n─── Phase 6.3: UPDATE / Overwrite Validation Tests ───');

  // Seed initial file for update tests
  await assertSucceeds(
    shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').put(dummyImageBytes, jpegMeta)
  );

  // Update 1: Valid replacement image -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').put(valid500KbBytes, jpegMeta)
    );
    reportTest('Update/Overwrite: Valid image payload overwrite is ALLOWED', true);
  } catch (e) {
    reportTest('Update/Overwrite: Valid image payload overwrite is ALLOWED', false, e);
  }

  // Update 2: Oversized replacement payload -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').put(oversizedBytes, jpegMeta)
    );
    reportTest('Update/Overwrite: Oversized replacement payload (> 1 MB) is DENIED', true);
  } catch (e) {
    reportTest('Update/Overwrite: Oversized replacement payload (> 1 MB) is DENIED', false, e);
  }

  // Update 3: Invalid MIME replacement payload (text/plain) -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').put(dummyImageBytes, plainTextMeta)
    );
    reportTest('Update/Overwrite: Invalid MIME replacement (text/plain) is DENIED', true);
  } catch (e) {
    reportTest('Update/Overwrite: Invalid MIME replacement (text/plain) is DENIED', false, e);
  }

  // Update 4: Cross-tenant overwrite attempt by Shopkeeper B -> DENY
  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/target_update.jpg').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Update/Overwrite: Cross-tenant overwrite attempt is DENIED', true);
  } catch (e) {
    reportTest('Update/Overwrite: Cross-tenant overwrite attempt is DENIED', false, e);
  }

  // ─── Phase 6.3: Metadata-Only UPDATE Behavior Tests ───
  console.log('\n─── Phase 6.3: Metadata-Only UPDATE Behavior Tests ───');

  // Meta-Update 1: Owner updates metadata on own valid catalog image (Compliant payload) -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        customMetadata: { altText: 'Grand Opening Special Banner' },
      })
    );
    reportTest('Meta-Update: Owner updating custom metadata on own catalog image is ALLOWED', true);
  } catch (e) {
    reportTest('Meta-Update: Owner updating custom metadata on own catalog image is ALLOWED', false, e);
  }

  // Meta-Update 2: Owner updates contentType to another allowed image MIME (image/webp) -> ALLOW
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        contentType: 'image/webp',
      })
    );
    reportTest('Meta-Update: Owner updating contentType to valid image/webp is ALLOWED', true);
  } catch (e) {
    reportTest('Meta-Update: Owner updating contentType to valid image/webp is ALLOWED', false, e);
  }

  // Meta-Update 3: Owner attempts to change contentType to text/plain -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        contentType: 'text/plain',
      })
    );
    reportTest('Meta-Update: Attempt to mutate contentType to text/plain via metadata update is DENIED', true);
  } catch (e) {
    reportTest('Meta-Update: Attempt to mutate contentType to text/plain via metadata update is DENIED', false, e);
  }

  // Meta-Update 4: Owner attempts to change contentType to application/json -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        contentType: 'application/json',
      })
    );
    reportTest('Meta-Update: Attempt to mutate contentType to application/json via metadata update is DENIED', true);
  } catch (e) {
    reportTest('Meta-Update: Attempt to mutate contentType to application/json via metadata update is DENIED', false, e);
  }

  // Meta-Update 5: Owner attempts to change contentType to application/octet-stream -> DENY
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        contentType: 'application/octet-stream',
      })
    );
    reportTest('Meta-Update: Attempt to mutate contentType to application/octet-stream is DENIED', true);
  } catch (e) {
    reportTest('Meta-Update: Attempt to mutate contentType to application/octet-stream is DENIED', false, e);
  }

  // Meta-Update 6: Cross-tenant metadata update by Shopkeeper B on Shop A -> DENY
  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        customMetadata: { hacked: 'true' },
      })
    );
    reportTest('Meta-Update: Cross-tenant metadata update by Shopkeeper B is DENIED', true);
  } catch (e) {
    reportTest('Meta-Update: Cross-tenant metadata update by Shopkeeper B is DENIED', false, e);
  }

  // Meta-Update 7: Customer metadata update on Shop A -> DENY
  try {
    await assertFails(
      customerStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        customMetadata: { rating: '5' },
      })
    );
    reportTest('Meta-Update: Customer metadata update is DENIED', true);
  } catch (e) {
    reportTest('Meta-Update: Customer metadata update is DENIED', false, e);
  }

  // Meta-Update 8: Anonymous metadata update on Shop A -> DENY
  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        customMetadata: { anon: 'true' },
      })
    );
    reportTest('Meta-Update: Anonymous metadata update is DENIED', true);
  } catch (e) {
    reportTest('Meta-Update: Anonymous metadata update is DENIED', false, e);
  }

  // Meta-Update 9: Attacker attempts to spoof customMetadata.shopId / admin role -> DENY
  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        customMetadata: { shopId: 'shop_A', role: 'admin', admin: 'true' },
      })
    );
    reportTest('Meta-Update: Metadata spoofing cannot bypass tenant authorization on update', true);
  } catch (e) {
    reportTest('Meta-Update: Metadata spoofing cannot bypass tenant authorization on update', false, e);
  }

  // Meta-Update 10: Admin metadata update across shops -> ALLOW
  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_A/banners/target_update.jpg').updateMetadata({
        customMetadata: { verifiedByAdmin: 'true' },
      })
    );
    reportTest('Meta-Update: Platform Admin metadata update across shops is ALLOWED', true);
  } catch (e) {
    reportTest('Meta-Update: Platform Admin metadata update across shops is ALLOWED', false, e);
  }

  console.log('\n─── Phase 6.3: DELETE Behavior Tests (request.resource null safety) ───');

  // Delete 1: Direct shopkeeper delete is strictly DENIED by Storage Rules (mandatory backend delegation)
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/target_update.jpg').delete()
    );
    reportTest('Delete: Direct shopkeeper delete is DENIED by Storage Rules (enforcing trusted backend gate)', true);
  } catch (e) {
    reportTest('Delete: Direct shopkeeper delete is DENIED by Storage Rules (enforcing trusted backend gate)', false, e);
  }

  // Re-seed for cross-actor delete tests
  await assertSucceeds(
    adminStorage.ref('shops/shop_A/banners/delete_test.jpg').put(dummyImageBytes, jpegMeta)
  );

  // Delete 2: Cross-tenant delete by Shopkeeper B -> DENY
  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/delete_test.jpg').delete()
    );
    reportTest('Delete: Cross-tenant delete is DENIED', true);
  } catch (e) {
    reportTest('Delete: Cross-tenant delete is DENIED', false, e);
  }

  // Delete 3: Customer delete -> DENY
  try {
    await assertFails(
      customerStorage.ref('shops/shop_A/banners/delete_test.jpg').delete()
    );
    reportTest('Delete: Customer delete is DENIED', true);
  } catch (e) {
    reportTest('Delete: Customer delete is DENIED', false, e);
  }

  // Delete 4: Anonymous delete -> DENY
  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/banners/delete_test.jpg').delete()
    );
    reportTest('Delete: Anonymous delete is DENIED', true);
  } catch (e) {
    reportTest('Delete: Anonymous delete is DENIED', false, e);
  }

  // Delete 5: Admin delete across shops -> ALLOW
  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_A/banners/delete_test.jpg').delete()
    );
    reportTest('Delete: Admin delete across shops is ALLOWED', true);
  } catch (e) {
    reportTest('Delete: Admin delete across shops is ALLOWED', false, e);
  }

  console.log('\n─── Phase 6.3: MIME Spoofing & Byte-Level Security Tests ───');

  // MIME Spoofing 1: Executable payload declared as image/jpeg
  const executableBytes = Buffer.from([0x4d, 0x5a, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00]); // DOS/PE "MZ" header
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/items/spoof_pe.jpg').put(executableBytes, jpegMeta)
    );
    reportTest('MIME Spoofing: Rules validate metadata/size; raw byte-level inspection requires backend pipeline', true);
  } catch (e) {
    reportTest('MIME Spoofing: Rules validate metadata/size; raw byte-level inspection requires backend pipeline', false, e);
  }

  // MIME Spoofing 2: Plain text bytes declared as image/png
  const plainTextContent = Buffer.from('console.log("malicious code");');
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/items/spoof_js.png').put(plainTextContent, pngMeta)
    );
    reportTest('MIME Spoofing: Text bytes with image/png metadata allowed by rules metadata check', true);
  } catch (e) {
    reportTest('MIME Spoofing: Text bytes with image/png metadata allowed by rules metadata check', false, e);
  }

  // Clean up spoofed test files
  try { await shopkeeperAStorage.ref('shops/shop_A/items/spoof_pe.jpg').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/items/spoof_js.png').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/banners/size_500kb.jpg').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/banners/size_exact_1mb.jpg').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/items/valid_jpeg.jpg').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/items/valid_png.png').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/items/valid_webp.webp').delete(); } catch (_) {}
  try { await shopkeeperAStorage.ref('shops/shop_A/items/1788960743164_burger_combo.jpg').delete(); } catch (_) {}

  // ─── PHASE 6.4: ADVANCED DELETE, OVERWRITE & URL BYPASS TESTS ───
  console.log('\n─── Phase 6.4: Advanced Delete, Overwrite & URL Bypass Tests ───');

  // Seed baseline objects for Phase 6.4 tests
  await assertSucceeds(
    adminStorage.ref('shops/shop_A/banners/64_active_banner.jpg').put(dummyImageBytes, jpegMeta)
  );
  await assertSucceeds(
    adminStorage.ref('shops/shop_A/items/64_order_item.jpg').put(dummyImageBytes, jpegMeta)
  );

  // 6.4.1 URL Possession Non-Privilege: Customer possessing public URL cannot delete object
  try {
    await assertFails(
      customerStorage.ref('shops/shop_A/banners/64_active_banner.jpg').delete()
    );
    reportTest('6.4.1 URL Non-Privilege: Customer possessing asset path/URL cannot delete', true);
  } catch (e) {
    reportTest('6.4.1 URL Non-Privilege: Customer possessing asset path/URL cannot delete', false, e);
  }

  // 6.4.2 URL Possession Non-Privilege: Anonymous user possessing public URL cannot delete object
  try {
    await assertFails(
      unauthStorage.ref('shops/shop_A/banners/64_active_banner.jpg').delete()
    );
    reportTest('6.4.2 URL Non-Privilege: Anonymous actor possessing asset path/URL cannot delete', true);
  } catch (e) {
    reportTest('6.4.2 URL Non-Privilege: Anonymous actor possessing asset path/URL cannot delete', false, e);
  }

  // 6.4.3 URL Possession Non-Privilege: Cross-tenant shopkeeper possessing URL cannot delete object
  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/64_active_banner.jpg').delete()
    );
    reportTest('6.4.3 URL Non-Privilege: Cross-shop shopkeeper possessing foreign URL cannot delete', true);
  } catch (e) {
    reportTest('6.4.3 URL Non-Privilege: Cross-shop shopkeeper possessing foreign URL cannot delete', false, e);
  }

  // 6.4.4 Overwrite Non-Privilege: Cross-tenant shopkeeper possessing URL cannot overwrite object
  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/64_active_banner.jpg').put(dummyImageBytes, jpegMeta)
    );
    reportTest('6.4.4 Overwrite Non-Privilege: Cross-shop shopkeeper cannot overwrite existing asset', true);
  } catch (e) {
    reportTest('6.4.4 Overwrite Non-Privilege: Cross-shop shopkeeper cannot overwrite existing asset', false, e);
  }

  // 6.4.5 Overwrite Non-Privilege: Customer cannot overwrite existing asset
  try {
    await assertFails(
      customerStorage.ref('shops/shop_A/banners/64_active_banner.jpg').put(dummyImageBytes, jpegMeta)
    );
    reportTest('6.4.5 Overwrite Non-Privilege: Customer cannot overwrite existing asset', true);
  } catch (e) {
    reportTest('6.4.5 Overwrite Non-Privilege: Customer cannot overwrite existing asset', false, e);
  }

  // 6.4.6 Encoded Path / Traversal Delete Attack: Encoded slashes or traversal paths cannot delete
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/%2e%2e%2fsecret.jpg').delete()
    );
    reportTest('6.4.6 Path Sanitization: Encoded path traversal delete attempt is DENIED', true);
  } catch (e) {
    reportTest('6.4.6 Path Sanitization: Encoded path traversal delete attempt is DENIED', false, e);
  }

  // 6.4.7 Non-Catalog Path Delete Attack: Deleting outside catalog folders is DENIED
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/internal/config.json').delete()
    );
    reportTest('6.4.7 Path Sanitization: Deletion outside catalog folders is DENIED', true);
  } catch (e) {
    reportTest('6.4.7 Path Sanitization: Deletion outside catalog folders is DENIED', false, e);
  }

  // 6.4.8 Concurrency & Independent Path Creation: Concurrent uploads to distinct timestamped paths succeed independently
  try {
    const upload1 = shopkeeperAStorage.ref('shops/shop_A/banners/1788990001_banner.jpg').put(dummyImageBytes, jpegMeta);
    const upload2 = shopkeeperAStorage.ref('shops/shop_A/banners/1788990002_banner.jpg').put(dummyImageBytes, jpegMeta);
    await Promise.all([assertSucceeds(upload1), assertSucceeds(upload2)]);
    reportTest('6.4.8 Concurrency: Concurrent unique timestamp uploads succeed without collision', true);
  } catch (e) {
    reportTest('6.4.8 Concurrency: Concurrent unique timestamp uploads succeed without collision', false, e);
  }

  // 6.4.9 Lifecycle Ordering: Owner uploads replacement; direct shopkeeper delete blocked; backend/admin cleans up
  try {
    // Step 1: Upload new asset
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/1788990003_new.jpg').put(dummyImageBytes, jpegMeta)
    );
    // Step 2: Direct delete old asset by shopkeeper is DENIED by Storage Rules
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/1788990001_banner.jpg').delete()
    );
    // Step 3: Admin / backend cleanup of old asset succeeds
    await assertSucceeds(
      adminStorage.ref('shops/shop_A/banners/1788990001_banner.jpg').delete()
    );
    reportTest('6.4.9 Lifecycle Ordering: Upload replacement before backend cleaning old asset succeeds', true);
  } catch (e) {
    reportTest('6.4.9 Lifecycle Ordering: Upload replacement before backend cleaning old asset succeeds', false, e);
  }

  // 6.4.10 Stale / Missing Object Delete Safety: Deleting already-deleted object returns object-not-found
  try {
    let errorCaught = null;
    try {
      await adminStorage.ref('shops/shop_A/banners/1788990001_banner.jpg').delete();
    } catch (err) {
      errorCaught = err;
    }
    assert(errorCaught && (errorCaught.code === 'storage/object-not-found' || errorCaught.message.includes('does not exist')), 'Must throw object-not-found');
    reportTest('6.4.10 Stale Delete: Deleting non-existent/already-deleted object safely returns object-not-found', true);
  } catch (e) {
    reportTest('6.4.10 Stale Delete: Deleting non-existent/already-deleted object safely returns object-not-found', false, e);
  }

  // 6.4.11 Historical Order Snapshot Isolation: Deletion of historical item image does not allow cross-shop deletion
  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/items/64_order_item.jpg').delete()
    );
    reportTest('6.4.11 Historical Asset Isolation: Cross-shop deletion of historical item is DENIED', true);
  } catch (e) {
    reportTest('6.4.11 Historical Asset Isolation: Cross-shop deletion of historical item is DENIED', false, e);
  }

  // 6.4.12 Platform Admin Controlled Deletion: Admin can delete across all shops
  try {
    await assertSucceeds(
      adminStorage.ref('shops/shop_A/banners/1788990002_banner.jpg').delete()
    );
    reportTest('6.4.12 Admin Authority: Platform admin can perform controlled deletion across shops', true);
  } catch (e) {
    reportTest('6.4.12 Admin Authority: Platform admin can perform controlled deletion across shops', false, e);
  }

  // 6.4.13 Metadata Metageneration Validation: Owner metadata update on active banner succeeds
  try {
    await assertSucceeds(
      shopkeeperAStorage.ref('shops/shop_A/banners/64_active_banner.jpg').updateMetadata({
        customMetadata: { lastAudited: 'Phase6.4' }
      })
    );
    reportTest('6.4.13 Metadata Concurrency: Owner metadata update on existing asset is ALLOWED', true);
  } catch (e) {
    reportTest('6.4.13 Metadata Concurrency: Owner metadata update on existing asset is ALLOWED', false, e);
  }

  // 6.4.14 Direct-Delete Attack Test: Owner directly calling Storage delete on active banner (bypassing Flutter)
  await assertSucceeds(
    adminStorage.ref('shops/shop_A/banners/direct_attack_banner.jpg').put(dummyImageBytes, jpegMeta)
  );
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/direct_attack_banner.jpg').delete()
    );
    reportTest('6.4.14 Direct-Delete Attack: Authenticated Shopkeeper A direct Storage delete on active banner is DENIED by Storage Rules', true);
  } catch (e) {
    reportTest('6.4.14 Direct-Delete Attack: Authenticated Shopkeeper A direct Storage delete on active banner is DENIED by Storage Rules', false, e);
  }
  try { await adminStorage.ref('shops/shop_A/banners/direct_attack_banner.jpg').delete(); } catch (_) {}

  // 6.4.15 Direct-Delete Attack Test: Owner directly calling Storage delete on active logo (bypassing Flutter)
  await assertSucceeds(
    adminStorage.ref('shops/shop_A/logos/direct_attack_logo.jpg').put(dummyImageBytes, jpegMeta)
  );
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/logos/direct_attack_logo.jpg').delete()
    );
    reportTest('6.4.15 Direct-Delete Attack: Authenticated Shopkeeper A direct Storage delete on active logo is DENIED by Storage Rules', true);
  } catch (e) {
    reportTest('6.4.15 Direct-Delete Attack: Authenticated Shopkeeper A direct Storage delete on active logo is DENIED by Storage Rules', false, e);
  }
  try { await adminStorage.ref('shops/shop_A/logos/direct_attack_logo.jpg').delete(); } catch (_) {}

  // 6.4.16 Direct-Delete Attack Test: Cross-tenant direct delete attempt by Shopkeeper B on Shop A banner
  await assertSucceeds(
    adminStorage.ref('shops/shop_A/banners/direct_attack_cross.jpg').put(dummyImageBytes, jpegMeta)
  );
  try {
    await assertFails(
      shopkeeperBStorage.ref('shops/shop_A/banners/direct_attack_cross.jpg').delete()
    );
    reportTest('6.4.16 Direct-Delete Cross-Shop: Foreign shopkeeper direct delete attack is strictly DENIED by Storage Rules', true);
  } catch (e) {
    reportTest('6.4.16 Direct-Delete Cross-Shop: Foreign shopkeeper direct delete attack is strictly DENIED by Storage Rules', false, e);
  }
  try { await adminStorage.ref('shops/shop_A/banners/direct_attack_cross.jpg').delete(); } catch (_) {}

  // 6.4.17 Direct-Delete Attack Test: Direct shopkeeper delete on unreferenced asset is ALSO DENIED by Storage Rules
  await assertSucceeds(
    adminStorage.ref('shops/shop_A/banners/unreferenced_shopkeeper_attempt.jpg').put(dummyImageBytes, jpegMeta)
  );
  try {
    await assertFails(
      shopkeeperAStorage.ref('shops/shop_A/banners/unreferenced_shopkeeper_attempt.jpg').delete()
    );
    reportTest('6.4.17 Direct-Delete Attack: Shopkeeper direct delete of unreferenced asset is DENIED by Storage Rules (mandatory backend delegation)', true);
  } catch (e) {
    reportTest('6.4.17 Direct-Delete Attack: Shopkeeper direct delete of unreferenced asset is DENIED by Storage Rules (mandatory backend delegation)', false, e);
  }
  try { await adminStorage.ref('shops/shop_A/banners/unreferenced_shopkeeper_attempt.jpg').delete(); } catch (_) {}

  // Cleanup remaining 6.4 test files
  try { await adminStorage.ref('shops/shop_A/banners/64_active_banner.jpg').delete(); } catch (_) {}
  try { await adminStorage.ref('shops/shop_A/items/64_order_item.jpg').delete(); } catch (_) {}
  try { await adminStorage.ref('shops/shop_A/banners/1788990003_new.jpg').delete(); } catch (_) {}

  // ─── PARTS 9 & 14: DEFAULT-DENY FALLBACK ────────────────────────────────────
  console.log('\n─── Parts 9 & 14: Default-Deny Fallback ───');

  try {
    await assertFails(
      shopkeeperAStorage.ref('random_bucket_root.txt').put(textBytes, textMetadata)
    );
    reportTest('Default-Deny: Shopkeeper write to unmapped root path is BLOCKED', true);
  } catch (e) {
    reportTest('Default-Deny: Shopkeeper write to unmapped root path is BLOCKED', false);
  }

  try {
    await assertFails(
      adminStorage.ref('system/security_override.bin').put(dummyImageBytes, jpegMeta)
    );
    reportTest('Default-Deny: Admin write to unmapped system/ path is BLOCKED', true);
  } catch (e) {
    reportTest('Default-Deny: Admin write to unmapped system/ path is BLOCKED', false);
  }

  try {
    await assertFails(
      adminStorage.ref('internal_backups/backup.db').getDownloadURL()
    );
    reportTest('Default-Deny: Unmapped path read fails closed even for Admin', true);
  } catch (e) {
    reportTest('Default-Deny: Unmapped path read fails closed even for Admin', false);
  }

  try {
    await assertFails(
      unauthStorage.ref('exports/daily_dump.csv').getDownloadURL()
    );
    reportTest('Default-Deny: Anonymous read of unmapped exports/ path is BLOCKED', true);
  } catch (e) {
    reportTest('Default-Deny: Anonymous read of unmapped exports/ path is BLOCKED', false);
  }

  console.log('\n======================================================================');
  console.log(`📊 TEST SUMMARY: ${passCount} / ${totalTests} TESTS PASSED`);
  console.log('======================================================================');

  if (passCount !== totalTests) {
    throw new Error(`Storage Rules Security Test Failures detected: ${totalTests - passCount} failed!`);
  }
}

async function main() {
  try {
    await setup();
    await runTests();
    console.log('🎉 ALL STORAGE RULES SECURITY & TENANT ISOLATION TESTS PASSED!');
    process.exit(0);
  } catch (err) {
    console.error('💥 Test suite encountered fatal error:', err);
    process.exit(1);
  } finally {
    if (testEnv) {
      await testEnv.cleanup();
    }
  }
}

main();
