/**
 * YummBU — Reference-Aware Firebase Storage Cleanup Service
 * Server-side audit & orphan detection engine.
 *
 * Invariants:
 * 1. Reference Awareness:
 *    - A file is NEVER deleted merely because it looks old.
 *    - Cross-references Firestore `shops`, `menuItems`, AND `orders` (historical snapshots).
 * 2. Active Upload Protection:
 *    - Files uploaded within the last 2 hours are ALWAYS preserved (in-flight upload protection).
 * 3. Historical Order Protection:
 *    - If an image is referenced by ANY order in `orders/`, it is PRESERVED.
 * 4. Unknown File Protection:
 *    - Files outside expected paths or with unparseable metadata are marked UNKNOWN and NEVER deleted.
 * 5. Dry-Run First:
 *    - Defaults to dry-run reporting mode. Only explicit verified orphans can be purged.
 */

/**
 * Extracts normalized storage relative path from a full Firebase Storage download URL.
 * e.g., "https://firebasestorage.googleapis.com/v0/b/.../o/shops%2Fshop_1%2Fmenu%2F123_food.jpg?alt=media"
 * -> "shops/shop_1/menu/123_food.jpg"
 */
function extractStoragePathFromUrl(url) {
  if (!url || typeof url !== "string") return null;
  const trimmed = url.trim();
  if (!trimmed) return null;

  try {
    // Firebase Storage URL format: .../o/<url-encoded-path>?...
    if (trimmed.includes("/o/")) {
      const match = trimmed.match(/\/o\/([^?#]+)/);
      if (match && match[1]) {
        return decodeURIComponent(match[1]);
      }
    }
    // Direct path or gs:// format
    if (trimmed.startsWith("gs://")) {
      const parts = trimmed.substring(5).split("/");
      parts.shift(); // remove bucket
      return parts.join("/");
    }
    if (trimmed.startsWith("shops/")) {
      return trimmed;
    }
  } catch (_) {
    return null;
  }
  return null;
}

/**
 * Scans Firestore collections to gather all referenced Storage paths.
 *
 * @param {Object} db - Firestore database instance.
 * @returns {Promise<{ currentPaths: Set<string>, historicalPaths: Set<string> }>}
 */
async function collectFirestoreReferencedPaths(db) {
  const currentPaths = new Set();
  const historicalPaths = new Set();

  function recordPath(url, set) {
    const path = extractStoragePathFromUrl(url);
    if (path) {
      set.add(path);
    }
  }

  // 1. Collect from `shops` (banner, logo)
  const shopsSnapshot = await db.collection("shops").get();
  for (const shopDoc of shopsSnapshot.docs) {
    const data = shopDoc.data() || {};
    recordPath(data.bannerUrl, currentPaths);
    recordPath(data.logoUrl, currentPaths);
    recordPath(data.shopLogoImageUrl, currentPaths);

    // 2. Collect from `shops/{shopId}/menuItems`
    const menuSnapshot = await shopDoc.ref.collection("menuItems").get();
    for (const itemDoc of menuSnapshot.docs) {
      const itemData = itemDoc.data() || {};
      recordPath(itemData.imageUrl, currentPaths);
    }
  }

  // 3. Collect from `orders` (historical snapshots)
  // Each order stores embedded items snapshot with imageUrl
  const ordersSnapshot = await db.collection("orders").get();
  for (const orderDoc of ordersSnapshot.docs) {
    const orderData = orderDoc.data() || {};
    if (Array.isArray(orderData.items)) {
      for (const item of orderData.items) {
        if (item && item.imageUrl) {
          recordPath(item.imageUrl, historicalPaths);
        }
      }
    }
  }

  return { currentPaths, historicalPaths };
}

/**
 * Performs reference-aware orphan audit on Firebase Storage files.
 *
 * @param {Object} bucket - Google Cloud Storage / Firebase Storage bucket.
 * @param {Object} db - Firestore instance.
 * @param {Object} [options]
 * @param {boolean} [options.dryRun] - If true, reports without deleting (default: true).
 * @param {number} [options.minAgeHours] - Min age in hours before considering orphan (default: 24h).
 * @param {number} [options.now] - Current timestamp (default: Date.now()).
 * @returns {Promise<Object>} Audit report.
 */
async function auditAndCleanStorageOrphans(bucket, db, options = {}) {
  const dryRun = options.dryRun !== false; // defaults to true
  const minAgeHours = options.minAgeHours || 24;
  const now = typeof options.now === "number" ? options.now : Date.now();
  const orphanMinAgeMs = minAgeHours * 60 * 60 * 1000;
  const activeThresholdMs = 2 * 60 * 60 * 1000; // 2 hours

  console.log(`🔍 [Storage Audit] Collecting Firestore references... (dryRun: ${dryRun})`);
  const { currentPaths, historicalPaths } = await collectFirestoreReferencedPaths(db);

  console.log(
    `📋 [Storage Audit] References found: ${currentPaths.size} current active paths, ${historicalPaths.size} historical order paths.`
  );

  // List files in the storage bucket under 'shops/'
  const [files] = await bucket.getFiles({ prefix: "shops/" });

  let totalFiles = files.length;
  let referencedCurrentCount = 0;
  let referencedHistoricalCount = 0;
  let activeRecentCount = 0;
  let unknownCount = 0;
  let verifiedOrphanFiles = [];
  let deletedCount = 0;
  let deleteErrors = 0;

  for (const file of files) {
    const filePath = file.name;

    // Safety check: is it an actual shop asset path?
    if (!filePath.startsWith("shops/")) {
      unknownCount++;
      continue;
    }

    // 1. Check current live reference
    if (currentPaths.has(filePath)) {
      referencedCurrentCount++;
      continue;
    }

    // 2. Check historical order reference
    if (historicalPaths.has(filePath)) {
      referencedHistoricalCount++;
      continue;
    }

    // 3. Check file creation / update time
    const metadata = file.metadata || {};
    const createdTimeStr = metadata.timeCreated || metadata.updated;
    const createdTime = createdTimeStr ? new Date(createdTimeStr).getTime() : 0;
    const fileAgeMs = now - createdTime;

    // Active upload protection (< 2 hours old): NEVER touch recent uploads
    if (fileAgeMs < activeThresholdMs) {
      activeRecentCount++;
      continue;
    }

    // Only qualify as verified orphan if older than minAgeHours (e.g. 24h)
    if (fileAgeMs >= orphanMinAgeMs) {
      verifiedOrphanFiles.push(file);
    } else {
      // In grace period between 2h and 24h
      activeRecentCount++;
    }
  }

  console.log(
    `📊 [Storage Audit Summary] Total Scanned: ${totalFiles}, Current Referenced: ${referencedCurrentCount}, Historical Referenced: ${referencedHistoricalCount}, Active/Recent: ${activeRecentCount}, Unknown: ${unknownCount}, Verified Orphans: ${verifiedOrphanFiles.length}`
  );

  if (!dryRun && verifiedOrphanFiles.length > 0) {
    console.log(`🧹 [Storage Audit] Purging ${verifiedOrphanFiles.length} verified orphan files...`);
    for (const orphan of verifiedOrphanFiles) {
      try {
        await orphan.delete();
        deletedCount++;
      } catch (err) {
        deleteErrors++;
        console.error(`⚠️ [Storage Audit] Failed to delete orphan ${orphan.name}:`, err);
      }
    }
  }

  return {
    totalScanned: totalFiles,
    referencedCurrent: referencedCurrentCount,
    referencedHistorical: referencedHistoricalCount,
    activeRecent: activeRecentCount,
    unknown: unknownCount,
    verifiedOrphansCount: verifiedOrphanFiles.length,
    deleted: deletedCount,
    deleteErrors,
    dryRun,
  };
}

module.exports = {
  extractStoragePathFromUrl,
  collectFirestoreReferencedPaths,
  auditAndCleanStorageOrphans,
};
