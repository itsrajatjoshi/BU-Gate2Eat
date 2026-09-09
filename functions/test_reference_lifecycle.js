/**
 * YummBU — Reference-Aware Storage Lifecycle, TOCTOU Race & Concurrency Test Suite
 * Phase 6.4: Advanced Storage Delete & Overwrite Protection (Round 4 Final Closure)
 */

const assert = require('assert');
const {
  parseStorageCatalogPath,
  checkActiveFirestoreReference,
  evaluateStorageAssetDeletion,
  executeStorageAssetDeletion,
  checkRateLimit,
  clearRateLimitHistory,
  extractStoragePath,
  deriveLifecycleDocId,
  isAssetRetired,
  assertAssetActivatable,
  updateCatalogImagePointer,
  MAX_CATALOG_SCAN_LIMIT,
} = require('./storage_reference_lifecycle');

console.log('🧪 Starting Phase 6.4 Reference-Aware Storage Lifecycle, TOCTOU & Scan Bounding Test Suite...\n');

let passCount = 0;
let totalTests = 0;

function report(name, passed, detail) {
  totalTests++;
  if (passed) {
    passCount++;
    console.log(`  ✅ [PASS] ${name}`);
  } else {
    console.error(`  ❌ [FAIL] ${name}`);
    if (detail) console.error(`     Detail:`, detail);
  }
}

// ─── MOCK FIRESTORE DATABASE WITH QUERY & MUTATION SUPPORT ──────────────────
function createMockDb(initialData = {}) {
  const data = JSON.parse(JSON.stringify(initialData));

  function createSubCollection(collName, docId, subCollName) {
    return {
      doc: (subDocId) => ({
        get: async () => {
          const docData = data[collName]?.[docId]?.[subCollName]?.[subDocId];
          return {
            exists: !!docData,
            data: () => docData || {},
          };
        },
        set: async (newData) => {
          if (!data[collName]) data[collName] = {};
          if (!data[collName][docId]) data[collName][docId] = {};
          if (!data[collName][docId][subCollName]) data[collName][docId][subCollName] = {};
          data[collName][docId][subCollName][subDocId] = { ...newData };
        },
        update: async (patch) => {
          if (!data[collName]?.[docId]?.[subCollName]?.[subDocId]) {
            data[collName][docId][subCollName][subDocId] = {};
          }
          Object.assign(data[collName][docId][subCollName][subDocId], patch);
        },
      }),
      where: (field, op, val) => ({
        limit: (n) => ({
          get: async () => {
            const subDocs = data[collName]?.[docId]?.[subCollName] || {};
            const matches = Object.entries(subDocs).filter(([_, d]) => {
              if (op === '==') return d[field] === val;
              return false;
            }).slice(0, n);
            return {
              docs: matches.map(([id, d]) => ({
                id,
                data: () => d,
              })),
            };
          },
        }),
      }),
      limit: (n) => ({
        get: async () => {
          const subDocs = data[collName]?.[docId]?.[subCollName] || {};
          const keys = Object.keys(subDocs).slice(0, n);
          return {
            docs: keys.map((id) => ({
              id,
              data: () => subDocs[id],
            })),
          };
        },
      }),
      get: async () => {
        const subDocs = data[collName]?.[docId]?.[subCollName] || {};
        return {
          docs: Object.keys(subDocs).map((id) => ({
            id,
            data: () => subDocs[id],
          })),
        };
      },
    };
  }

  return {
    _rawData: data,
    collection: (collName) => ({
      doc: (docId) => ({
        get: async () => ({
          exists: !!data[collName]?.[docId],
          data: () => data[collName]?.[docId] || {},
        }),
        set: async (newData) => {
          if (!data[collName]) data[collName] = {};
          data[collName][docId] = { ...newData };
        },
        update: async (patch) => {
          if (!data[collName]?.[docId]) data[collName][docId] = {};
          Object.assign(data[collName][docId], patch);
        },
        collection: (subCollName) => createSubCollection(collName, docId, subCollName),
      }),
    }),
  };
}

async function runTests() {
  clearRateLimitHistory();

  console.log('─── Section 1: Storage Catalog Path Parser & Validation Tests ───');

  const p1 = parseStorageCatalogPath('shops/shop_A/banner/1788990001_banner.jpg');
  report('Path Parser: Valid banner path parses correctly', p1.valid && p1.shopId === 'shop_A' && p1.folder === 'banner');

  const p2 = parseStorageCatalogPath('shops/shop_A/items/1788990002_burger.png');
  report('Path Parser: Valid menu item path parses correctly', p2.valid && p2.shopId === 'shop_A' && p2.folder === 'items');

  const p3 = parseStorageCatalogPath('shops/shop_A/internal/secrets.json');
  report('Path Parser: Non-catalog folder is rejected', !p3.valid);

  const p4 = parseStorageCatalogPath('shops/shop_A/banner/../secret.jpg');
  report('Path Parser: Path traversal in filename is rejected', !p4.valid);

  const p5 = parseStorageCatalogPath('shops/shop_A/banner/malicious.exe');
  report('Path Parser: Executable extension is rejected', !p5.valid);

  console.log('\n─── Section 2: Active-Reference Detection Tests ───');

  const mockDb = createMockDb({
    shops: {
      shop_A: {
        name: 'Shop A',
        bannerUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/shops%2Fshop_A%2Fbanner%2F1788990001_banner.jpg?alt=media',
        shopLogoImageUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/shops%2Fshop_A%2Flogo%2F1788990002_logo.jpg?alt=media',
        menuItems: {
          item_101: {
            name: 'Deluxe Burger',
            imageUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/shops%2Fshop_A%2Fitems%2F1788990003_burger.jpg?alt=media',
          },
        },
        categories: {
          cat_201: {
            name: 'Fast Food',
            imageUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/shops%2Fshop_A%2Fcategories%2F1788990004_fastfood.jpg?alt=media',
          },
        },
      },
    },
  });

  const r1 = await checkActiveFirestoreReference(mockDb, 'shop_A', 'banner', '1788990001_banner.jpg');
  report('Active Reference: Correctly identifies currently active shop banner', r1.isReferenced && r1.referenceType === 'ACTIVE_SHOP_BANNER');

  const r2 = await checkActiveFirestoreReference(mockDb, 'shop_A', 'banner', '1788999999_old_banner.jpg');
  report('Active Reference: Unreferenced banner correctly returns isReferenced=false', !r2.isReferenced);

  const r3 = await checkActiveFirestoreReference(mockDb, 'shop_A', 'logo', '1788990002_logo.jpg');
  report('Active Reference: Correctly identifies currently active shop logo', r3.isReferenced && r3.referenceType === 'ACTIVE_SHOP_LOGO');

  const r4 = await checkActiveFirestoreReference(mockDb, 'shop_A', 'items', '1788990003_burger.jpg');
  report('Active Reference: Correctly identifies currently active menu item photo', r4.isReferenced && r4.referenceType === 'ACTIVE_MENU_ITEM');

  const r5 = await checkActiveFirestoreReference(mockDb, 'shop_A', 'items', '1788999999_old_burger.jpg');
  report('Active Reference: Replaced/unreferenced menu item photo correctly returns isReferenced=false', !r5.isReferenced);

  const r6 = await checkActiveFirestoreReference(mockDb, 'shop_A', 'categories', '1788990004_fastfood.jpg');
  report('Active Reference: Correctly identifies currently active category photo', r6.isReferenced && r6.referenceType === 'ACTIVE_CATEGORY');

  console.log('\n─── Section 3: Authoritative Reference-Aware Deletion Evaluations ───');

  const ownerTokenA = { role: 'shopkeeper', shopId: 'shop_A', uid: 'shopkeeper_a' };
  const ownerTokenB = { role: 'shopkeeper', shopId: 'shop_B', uid: 'shopkeeper_b' };
  const customerToken = { role: 'customer', uid: 'cust_101' };
  const adminToken = { role: 'admin', uid: 'admin_root' };

  const e1 = await evaluateStorageAssetDeletion(mockDb, ownerTokenA, 'shops/shop_A/banner/1788990001_banner.jpg');
  report('Authoritative Delete: Deletion of actively referenced shop banner is REFUSED', !e1.allowed && e1.code === 'ACTIVE_REFERENCE_PROTECTION');

  const e2 = await evaluateStorageAssetDeletion(mockDb, ownerTokenA, 'shops/shop_A/logo/1788990002_logo.jpg');
  report('Authoritative Delete: Deletion of actively referenced shop logo is REFUSED', !e2.allowed && e2.code === 'ACTIVE_REFERENCE_PROTECTION');

  const e3 = await evaluateStorageAssetDeletion(mockDb, ownerTokenA, 'shops/shop_A/items/1788990003_burger.jpg');
  report('Authoritative Delete: Deletion of actively referenced menu item photo is REFUSED', !e3.allowed && e3.code === 'ACTIVE_REFERENCE_PROTECTION');

  const e4 = await evaluateStorageAssetDeletion(mockDb, ownerTokenA, 'shops/shop_A/categories/1788990004_fastfood.jpg');
  report('Authoritative Delete: Deletion of actively referenced category photo is REFUSED', !e4.allowed && e4.code === 'ACTIVE_REFERENCE_PROTECTION');

  const e5 = await evaluateStorageAssetDeletion(mockDb, ownerTokenA, 'shops/shop_A/banner/1788999999_old_banner.jpg');
  report('Authoritative Delete: Deletion of unreferenced old banner is ALLOWED', e5.allowed && e5.code === 'OK');

  const e6 = await evaluateStorageAssetDeletion(mockDb, ownerTokenA, 'shops/shop_A/items/1788999999_old_burger.jpg');
  report('Authoritative Delete: Deletion of unreferenced old menu item photo is ALLOWED', e6.allowed && e6.code === 'OK');

  const e7 = await evaluateStorageAssetDeletion(mockDb, ownerTokenB, 'shops/shop_A/banner/1788999999_old_banner.jpg');
  report('Authoritative Delete: Cross-tenant deletion by Shopkeeper B is DENIED', !e7.allowed && e7.code === 'PERMISSION_DENIED');

  const e8 = await evaluateStorageAssetDeletion(mockDb, customerToken, 'shops/shop_A/banner/1788999999_old_banner.jpg');
  report('Authoritative Delete: Customer deletion attempt is DENIED', !e8.allowed && e8.code === 'PERMISSION_DENIED');

  const e9 = await evaluateStorageAssetDeletion(mockDb, null, 'shops/shop_A/banner/1788999999_old_banner.jpg');
  report('Authoritative Delete: Anonymous deletion attempt is DENIED', !e9.allowed && e9.code === 'UNAUTHENTICATED');

  const e10 = await evaluateStorageAssetDeletion(mockDb, adminToken, 'shops/shop_A/banner/1788999999_old_banner.jpg');
  report('Authoritative Delete: Platform Admin can delete unreferenced asset across shops', e10.allowed && e10.code === 'OK');

  const e11 = await evaluateStorageAssetDeletion(mockDb, adminToken, 'shops/shop_A/banner/1788990001_banner.jpg');
  report('Authoritative Delete: Platform Admin deletion of active reference via backend is REFUSED', !e11.allowed && e11.code === 'ACTIVE_REFERENCE_PROTECTION');

  console.log('\n─── Section 4: End-to-End Lifecycle Scenarios (G through X) ───');

  const mockBucket = {
    _deletedFiles: [],
    file: (path) => ({
      exists: async () => {
        if (path.includes('9999999999') || path.includes('8888888888')) {
          return [false];
        }
        return [!mockBucket._deletedFiles.includes(path)];
      },
      delete: async () => {
        if (mockBucket._deletedFiles.includes(path)) {
          const err = new Error('No such object');
          err.code = 404;
          throw err;
        }
        mockBucket._deletedFiles.push(path);
      },
    }),
  };

  // G. Active banner -> DENY
  const execG = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/banner/1788990001_banner.jpg');
  report('G. Authenticated shopkeeper deleting active banner is REFUSED', !execG.success && execG.code === 'ACTIVE_REFERENCE_PROTECTION');

  // H. Inactive banner -> ALLOW
  const execH = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/banner/1788999999_old_banner.jpg');
  report('H. Authenticated shopkeeper deleting inactive banner SUCCEEDS', execH.success && execH.deleted);

  // I. Active logo -> DENY
  const execI = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/logo/1788990002_logo.jpg');
  report('I. Authenticated shopkeeper deleting active logo is REFUSED', !execI.success && execI.code === 'ACTIVE_REFERENCE_PROTECTION');

  // J. Inactive logo -> ALLOW
  const execJ = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/logo/1788999999_old_logo.jpg');
  report('J. Authenticated shopkeeper deleting inactive logo SUCCEEDS', execJ.success && execJ.deleted);

  // K. Active menu item image -> DENY
  const execK = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/items/1788990003_burger.jpg');
  report('K. Authenticated shopkeeper deleting active menu item is REFUSED', !execK.success && execK.code === 'ACTIVE_REFERENCE_PROTECTION');

  // L. Inactive menu item image -> ALLOW
  const execL = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/items/1788999999_old_burger.jpg');
  report('L. Authenticated shopkeeper deleting inactive menu item SUCCEEDS', execL.success && execL.deleted);

  // M. Active category image -> DENY
  const execM = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/categories/1788990004_fastfood.jpg');
  report('M. Authenticated shopkeeper deleting active category is REFUSED', !execM.success && execM.code === 'ACTIVE_REFERENCE_PROTECTION');

  // N. Inactive category image -> ALLOW
  const execN = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/categories/1788999999_old_fastfood.jpg');
  report('N. Authenticated shopkeeper deleting inactive category SUCCEEDS', execN.success && execN.deleted);

  // O. Cross-tenant request -> DENY
  const execO = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenB, 'shops/shop_A/banner/1788990001_banner.jpg');
  report('O. Cross-tenant deletion request is DENIED', !execO.success && execO.code === 'PERMISSION_DENIED');

  // P. Customer request -> DENY
  const execP = await executeStorageAssetDeletion(mockDb, mockBucket, customerToken, 'shops/shop_A/banner/1788990001_banner.jpg');
  report('P. Customer deletion request is DENIED', !execP.success && execP.code === 'PERMISSION_DENIED');

  // Q. Anonymous request -> DENY
  const execQ = await executeStorageAssetDeletion(mockDb, mockBucket, null, 'shops/shop_A/banner/1788990001_banner.jpg');
  report('Q. Anonymous deletion request is DENIED', !execQ.success && execQ.code === 'UNAUTHENTICATED');

  // R. Admin request on unreferenced asset -> ALLOW
  const execR = await executeStorageAssetDeletion(mockDb, mockBucket, adminToken, 'shops/shop_A/banner/1788999999_old_banner.jpg');
  report('R. Admin deletion request on unreferenced asset SUCCEEDS', execR.success);

  // S. Duplicate delete -> Idempotent safe outcome
  const execS = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/banner/1788999999_old_banner.jpg');
  report('S. Duplicate delete of already-removed asset returns safe idempotent success', execS.success && execS.alreadyAbsent === true);

  // T. Already absent object -> Idempotent safe outcome
  const execT = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/banner/9999999999_never_existed.jpg');
  report('T. Non-existent unreferenced asset deletion returns safe idempotent success', execT.success && execT.alreadyAbsent === true);

  // U. Malformed Storage URL -> DENY
  const execU = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'not_a_valid_url_or_path');
  report('U. Malformed storage path/URL is rejected with INVALID_ARGUMENT', !execU.success && execU.code === 'INVALID_ARGUMENT');

  // V. Encoded traversal -> DENY
  const execV = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, 'shops/shop_A/banner/..%2Fsecret.jpg');
  report('V. Encoded path traversal is rejected with INVALID_ARGUMENT', !execV.success && execV.code === 'INVALID_ARGUMENT');

  // W. Foreign-shop URL -> DENY
  const foreignUrl = 'https://firebasestorage.googleapis.com/v0/b/app/o/shops%2Fshop_B%2Fbanner%2F1788990001_banner.jpg?alt=media';
  const execW = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, foreignUrl);
  report('W. Full download URL of foreign shop is rejected with PERMISSION_DENIED', !execW.success && execW.code === 'PERMISSION_DENIED');

  // X. Own full download URL unreferenced -> ALLOW
  const ownUnrefUrl = 'https://firebasestorage.googleapis.com/v0/b/app/o/shops%2Fshop_A%2Fitems%2F8888888888_old.jpg?alt=media';
  const execX = await executeStorageAssetDeletion(mockDb, mockBucket, ownerTokenA, ownUnrefUrl);
  report('X. Full download URL parsing for unreferenced asset SUCCEEDS', execX.success && execX.alreadyAbsent === true);

  console.log('\n─── Section 5: TOCTOU & Concurrency Race Mitigation Tests ───');

  const toctouDb = createMockDb({
    shops: {
      shop_race: {
        bannerUrl: 'shops/shop_race/banner/1000_other.jpg',
      },
    },
  });

  let interleavedWriteOccurred = false;
  const racingDb = {
    collection: (collName) => {
      const coll = toctouDb.collection(collName);
      return {
        doc: (docId) => {
          const docObj = coll.doc(docId);
          return {
            ...docObj,
            collection: (subColl) => {
              if (subColl === 'deletionIntents') {
                const sub = docObj.collection(subColl);
                return {
                  doc: (subId) => ({
                    set: async (val) => {
                      if (val.status === 'RETIRED') {
                        interleavedWriteOccurred = true;
                        toctouDb._rawData.shops.shop_race.bannerUrl = 'shops/shop_race/banner/2000_target.jpg';
                      }
                      return sub.doc(subId).set(val);
                    },
                  }),
                };
              }
              return docObj.collection(subColl);
            },
          };
        },
      };
    },
  };

  const raceToken = { role: 'shopkeeper', shopId: 'shop_race', uid: 'racer_1' };
  const execCaseA = await executeStorageAssetDeletion(racingDb, mockBucket, raceToken, 'shops/shop_race/banner/2000_target.jpg');
  report(
    'TOCTOU Case A: Interleaved pointer update during deletion workflow is detected and ABORTS physical delete',
    interleavedWriteOccurred && !execCaseA.success && execCaseA.code === 'ACTIVE_REFERENCE_PROTECTION' && execCaseA.toctouChecked === true
  );

  // CASE B: Asset referenced at start -> reference removed -> deletion succeeds
  toctouDb._rawData.shops.shop_race.bannerUrl = 'shops/shop_race/banner/3000_superseded.jpg';
  toctouDb._rawData.shops.shop_race.bannerUrl = 'shops/shop_race/banner/3001_new.jpg';
  const execCaseB = await executeStorageAssetDeletion(toctouDb, mockBucket, raceToken, 'shops/shop_race/banner/3000_superseded.jpg');
  report(
    'TOCTOU Case B: Asset referenced then cleanly unreferenced succeeds deletion',
    execCaseB.success && execCaseB.deleted && execCaseB.toctouChecked === true
  );

  // CASE C: Concurrent replacement: Device A uploads A, Device B uploads B. Pointer points to B.
  toctouDb._rawData.shops.shop_race.bannerUrl = 'shops/shop_race/banner/4002_device_B.jpg';
  const execCaseC = await executeStorageAssetDeletion(toctouDb, mockBucket, raceToken, 'shops/shop_race/banner/4001_device_A.jpg');
  report(
    'TOCTOU Case C: Stale cleanup targets superseded object while active pointer remains protected',
    execCaseC.success && toctouDb._rawData.shops.shop_race.bannerUrl === 'shops/shop_race/banner/4002_device_B.jpg'
  );

  console.log('\n─── Section 6: Collection Scan Bounding & Abuse Protection Tests ───');

  const massiveMenu = {};
  for (let i = 1; i <= 200; i++) {
    massiveMenu[`item_${i}`] = {
      name: `Item ${i}`,
      imageUrl: `shops/shop_huge/items/1788990000_${i}.jpg`,
    };
  }

  const hugeCatalogDb = createMockDb({
    shops: {
      shop_huge: {
        name: 'Huge Shop',
        menuItems: massiveMenu,
      },
    },
  });

  const scanExceededResult = await checkActiveFirestoreReference(
    hugeCatalogDb,
    'shop_huge',
    'items',
    'non_existent_unindexed.jpg'
  );
  report(
    'Scan Bounding: Collections exceeding MAX_CATALOG_SCAN_LIMIT (150) fail closed with SCAN_BOUND_EXCEEDED',
    scanExceededResult.isReferenced && scanExceededResult.referenceType === 'SCAN_BOUND_EXCEEDED'
  );

  const targetedResult = await checkActiveFirestoreReference(
    hugeCatalogDb,
    'shop_huge',
    'items',
    '1788990000_42.jpg',
    'shops/shop_huge/items/1788990000_42.jpg'
  );
  report(
    'Targeted Query: Exact indexed lookup identifies active reference without unbounded scan',
    targetedResult.isReferenced && targetedResult.strategy === 'EXACT_INDEXED_QUERY'
  );

  console.log('\n─── Section 7: Rate Limiting & Abuse Protection Tests ───');

  let rateLimitedHit = false;
  for (let i = 0; i < 25; i++) {
    const rateEval = await evaluateStorageAssetDeletion(mockDb, ownerTokenA, `shops/shop_A/banner/unref_${i}.jpg`);
    if (!rateEval.allowed && rateEval.code === 'TOO_MANY_REQUESTS') {
      rateLimitedHit = true;
      break;
    }
  }
  report(
    'Rate Limiting: Exceeding 20 delete requests per minute triggers 429 TOO_MANY_REQUESTS',
    rateLimitedHit
  );

  console.log('\n─── Section 8: Round 4 Mandatory Adversarial Invariant Tests ───');

  // Adversarial Test 1: Actor A begins deletion of object X (enters RETIRED).
  // Actor B (authorized shopkeeper for same shop) attempts to set reference to X.
  // assertAssetActivatable MUST REJECT Actor B's attempt!
  const advDb = createMockDb({
    shops: {
      shop_adv: {
        name: 'Adversarial Test Shop',
        bannerUrl: 'shops/shop_adv/banner/999_initial.jpg',
      },
    },
  });

  const actorTokenA = { role: 'shopkeeper', shopId: 'shop_adv', uid: 'actor_A' };
  const targetObjX = 'shops/shop_adv/banner/1000_target_x.jpg';

  // Actor A begins deletion workflow -> target enters RETIRED state
  const advBucket = {
    file: (path) => ({
      exists: async () => [true],
      delete: async () => {},
    }),
  };

  // 1. Target is marked RETIRED in Firestore
  const retireDocId = deriveLifecycleDocId('banner', '1000_target_x.jpg');
  await advDb.collection('shops').doc('shop_adv')
    .collection('deletionIntents').doc(retireDocId).set({
      canonicalPath: targetObjX,
      shopId: 'shop_adv',
      folder: 'banner',
      fileName: '1000_target_x.jpg',
      status: 'RETIRED',
    });

  // 2. Actor B attempts to make X current banner
  let activationBlocked = false;
  try {
    await assertAssetActivatable(advDb, 'shop_adv', targetObjX);
  } catch (err) {
    activationBlocked = err.message.includes('permanently non-reactivable');
  }
  report(
    'Adversarial Invariant 1: Actor B attempt to activate RETIRED asset X is strictly REJECTED',
    activationBlocked
  );

  // Adversarial Test 2: Intent Collision Avoidance
  // Create shops/shop_A/banner/same.jpg and shops/shop_A/logo/same.jpg
  const docIdBanner = deriveLifecycleDocId('banner', 'same.jpg');
  const docIdLogo = deriveLifecycleDocId('logo', 'same.jpg');
  report(
    'Adversarial Invariant 2: Different catalog folders sharing identical filename produce isolated document IDs',
    typeof docIdBanner === 'string' && docIdBanner.length === 64 &&
    typeof docIdLogo === 'string' && docIdLogo.length === 64 &&
    docIdBanner !== docIdLogo
  );

  // Retire banner/same.jpg and assert logo/same.jpg is still active and not retired
  const collisionDb = createMockDb({
    shops: {
      shop_coll: {},
    },
  });
  await collisionDb.collection('shops').doc('shop_coll')
    .collection('deletionIntents').doc(docIdBanner).set({ status: 'RETIRED' });

  const bannerIsRetired = await isAssetRetired(collisionDb, 'shop_coll', 'banner', 'same.jpg');
  const logoIsRetired = await isAssetRetired(collisionDb, 'shop_coll', 'logo', 'same.jpg');
  report(
    'Adversarial Invariant 3: Retiring banner does NOT retire logo with identical filename (Zero Collision)',
    bannerIsRetired === true && logoIsRetired === false
  );

  // Adversarial Test 3: Canonical URL Normalization
  const canonicalExpected = 'shops/shop_norm/banner/hero.jpg';
  const url1 = 'https://firebasestorage.googleapis.com/v0/b/bucket/o/shops%2Fshop_norm%2Fbanner%2Fhero.jpg?alt=media&token=TOKEN_AAA';
  const url2 = 'https://firebasestorage.googleapis.com/v0/b/bucket/o/shops%2Fshop_norm%2Fbanner%2Fhero.jpg?alt=media&token=TOKEN_BBB';
  const url3 = 'gs://bucket/shops/shop_norm/banner/hero.jpg';
  const url4 = 'shops/shop_norm/banner/hero.jpg';
  const url5 = '/shops/shop_norm/banner/hero.jpg';

  const n1 = extractStoragePath(url1);
  const n2 = extractStoragePath(url2);
  const n3 = extractStoragePath(url3);
  const n4 = extractStoragePath(url4);
  const n5 = extractStoragePath(url5);

  report(
    'Adversarial Invariant 4: HTTPS with tokens, gs://, and relative paths all normalize to identical canonical path',
    n1 === canonicalExpected &&
    n2 === canonicalExpected &&
    n3 === canonicalExpected &&
    n4 === canonicalExpected &&
    n5 === canonicalExpected
  );

  // Adversarial Test 4: Rate Limiting Multi-Tenant Isolation
  clearRateLimitHistory();
  // Saturate shop_X
  for (let i = 0; i < 20; i++) {
    checkRateLimit('shop_X');
  }
  const shopXThrottled = checkRateLimit('shop_X').limited;
  const shopYAllowed = !checkRateLimit('shop_Y').limited;
  report(
    'Adversarial Invariant 5: Rate limit saturation on Shop X does not throttle Shop Y (Tenant Isolation)',
    shopXThrottled && shopYAllowed
  );

  // ── Section 9: Direct Firestore Reactivation & Lifecycle Mutation Adversarial Tests (Round 4) ──
  console.log('\n--- Section 9: Direct Firestore Reactivation & Lifecycle Mutation Adversarial Tests (Round 4) ---');

  // TEST A: Retire asset X -> Authorized shopkeeper attempt to update pointer to X -> MUST FAIL
  const testADb = createMockDb({
    shops: {
      shop_test_a: {
        bannerUrl: 'shops/shop_test_a/banner/old_banner.jpg',
      },
    },
  });
  // Mark asset X as RETIRED in deletionIntents
  const docIdAssetX = deriveLifecycleDocId('banner', 'target_x.jpg');
  await testADb.collection('shops').doc('shop_test_a')
    .collection('deletionIntents').doc(docIdAssetX).set({
      canonicalPath: 'shops/shop_test_a/banner/target_x.jpg',
      status: 'RETIRED',
    });

  let testAFailed = false;
  try {
    await updateCatalogImagePointer(
      testADb,
      { role: 'shopkeeper', shopId: 'shop_test_a' },
      {
        shopId: 'shop_test_a',
        targetType: 'shop',
        targetId: 'shop_test_a',
        field: 'bannerUrl',
        imageUrl: 'shops/shop_test_a/banner/target_x.jpg',
      }
    );
  } catch (err) {
    testAFailed = err.message.includes('ERR_ASSET_RETIRED') || err.message.includes('permanently non-reactivable');
  }
  report(
    'TEST A: Retire asset X -> authorized shopkeeper attempt to point to X -> strictly REJECTED',
    testAFailed
  );

  // TEST B: Retire banner/X -> Authorized shopkeeper activates logo/X -> MUST succeed if logo/X is not retired
  const testBDb = createMockDb({
    shops: {
      shop_test_b: {
        shopLogoImageUrl: '',
      },
    },
  });
  // Retire banner/X only
  const docIdBannerX = deriveLifecycleDocId('banner', 'shared_name.jpg');
  await testBDb.collection('shops').doc('shop_test_b')
    .collection('deletionIntents').doc(docIdBannerX).set({
      canonicalPath: 'shops/shop_test_b/banner/shared_name.jpg',
      status: 'RETIRED',
    });

  const resB = await updateCatalogImagePointer(
    testBDb,
    { role: 'shopkeeper', shopId: 'shop_test_b' },
    {
      shopId: 'shop_test_b',
      targetType: 'shop',
      targetId: 'shop_test_b',
      field: 'shopLogoImageUrl',
      imageUrl: 'shops/shop_test_b/logo/shared_name.jpg',
    }
  );
  report(
    'TEST B: Retire banner/X -> activating logo/X with same filename SUCCEEDS (Zero namespace cross-leak)',
    resB.success === true && testBDb._rawData.shops.shop_test_b.shopLogoImageUrl === 'shops/shop_test_b/logo/shared_name.jpg'
  );

  // TEST C: Retire X -> Backend tries stale reactivation -> MUST FAIL
  let testCFailed = false;
  try {
    await assertAssetActivatable(testADb, 'shop_test_a', 'shops/shop_test_a/banner/target_x.jpg');
  } catch (err) {
    testCFailed = err.message.includes('ERR_ASSET_RETIRED') || err.message.includes('permanently non-reactivable');
  }
  report(
    'TEST C: Retire X -> backend assertion assertAssetActivatable rejects stale reactivation',
    testCFailed
  );

  // TEST D: Two-device replacement race:
  // Device A sets pointer A, Device B sets pointer B.
  // Verify last valid pointer survives and retired object cannot be reactivated
  const testDDb = createMockDb({
    shops: {
      shop_test_d: {
        bannerUrl: 'shops/shop_test_d/banner/initial.jpg',
      },
    },
  });
  // Device A uploads A and updates pointer
  await updateCatalogImagePointer(
    testDDb,
    { role: 'shopkeeper', shopId: 'shop_test_d' },
    {
      shopId: 'shop_test_d',
      targetType: 'shop',
      targetId: 'shop_test_d',
      field: 'bannerUrl',
      imageUrl: 'shops/shop_test_d/banner/device_a.jpg',
    }
  );
  // Device B uploads B and updates pointer
  await updateCatalogImagePointer(
    testDDb,
    { role: 'shopkeeper', shopId: 'shop_test_d' },
    {
      shopId: 'shop_test_d',
      targetType: 'shop',
      targetId: 'shop_test_d',
      field: 'bannerUrl',
      imageUrl: 'shops/shop_test_d/banner/device_b.jpg',
    }
  );
  // Device A's banner is now unreferenced and retired
  const docIdDevA = deriveLifecycleDocId('banner', 'device_a.jpg');
  await testDDb.collection('shops').doc('shop_test_d')
    .collection('deletionIntents').doc(docIdDevA).set({
      status: 'RETIRED',
    });
  // Verify Device B is active
  const activeBannerD = testDDb._rawData.shops.shop_test_d.bannerUrl;
  // Verify Device A cannot be reactivated
  let devAReactivationBlocked = false;
  try {
    await updateCatalogImagePointer(
      testDDb,
      { role: 'shopkeeper', shopId: 'shop_test_d' },
      {
        shopId: 'shop_test_d',
        targetType: 'shop',
        targetId: 'shop_test_d',
        field: 'bannerUrl',
        imageUrl: 'shops/shop_test_d/banner/device_a.jpg',
      }
    );
  } catch (e) {
    devAReactivationBlocked = true;
  }
  report(
    'TEST D: Two-device replacement race: Device B active pointer survives, Device A retired & non-reactivable',
    activeBannerD === 'shops/shop_test_d/banner/device_b.jpg' && devAReactivationBlocked
  );

  // TEST E: Active reference discovered immediately before deletion -> Deletion MUST abort
  const testEDb = createMockDb({
    shops: {
      shop_test_e: {
        bannerUrl: 'shops/shop_test_e/banner/still_in_use.jpg',
      },
    },
  });
  const execResultE = await executeStorageAssetDeletion(
    testEDb,
    mockBucket,
    { role: 'shopkeeper', shopId: 'shop_test_e' },
    'shops/shop_test_e/banner/still_in_use.jpg'
  );
  report(
    'TEST E: Active reference present at pre-delete check -> deletion strictly ABORTED (ERR_ACTIVE_REFERENCE)',
    execResultE.success === false && execResultE.code === 'ACTIVE_REFERENCE_PROTECTION'
  );

  // TEST F: Folder-collision lifecycle IDs -> MUST remain isolated across all 4 catalog folders
  const idBanner = deriveLifecycleDocId('banner', 'common_asset.jpg');
  const idLogo = deriveLifecycleDocId('logo', 'common_asset.jpg');
  const idMenu = deriveLifecycleDocId('menu', 'common_asset.jpg');
  const idCategories = deriveLifecycleDocId('categories', 'common_asset.jpg');
  const setOfIds = new Set([idBanner, idLogo, idMenu, idCategories]);
  report(
    'TEST F: All 4 catalog folders (banner, logo, menu, categories) generate unique, non-colliding lifecycle IDs',
    setOfIds.size === 4 &&
    idBanner.length === 64 &&
    idLogo.length === 64 &&
    idMenu.length === 64 &&
    idCategories.length === 64
  );

  // TEST G: Sanitization collision prevention (a.b.jpg vs a_b.jpg)
  const idDot = deriveLifecycleDocId('banner', 'a.b.jpg');
  const idUnderscore = deriveLifecycleDocId('banner', 'a_b.jpg');
  report(
    'TEST G: Filename variations (a.b.jpg vs a_b.jpg) generate distinct SHA-256 lifecycle IDs (Zero sanitization collision)',
    idDot !== idUnderscore && idDot.length === 64 && idUnderscore.length === 64
  );

  console.log('\n======================================================================');
  console.log(`📊 TEST SUMMARY: ${passCount} / ${totalTests} TESTS PASSED`);
  console.log('======================================================================');

  if (passCount !== totalTests) {
    throw new Error(`Reference Lifecycle Test Failures detected: ${totalTests - passCount} failed!`);
  }
}

runTests().catch((err) => {
  console.error('💥 Fatal error in reference lifecycle test suite:', err);
  process.exit(1);
});
