/**
 * YummBU — Server-Authoritative Order Creation Engine (Phase 4.1)
 * 
 * Security Invariants:
 * 1. Customer UID derived strictly from authenticated authContext.
 * 2. Client customerId spoofing is strictly rejected (permission-denied).
 * 3. Shop existence and active status verified against authoritative catalog.
 * 4. Menu items verified against shop catalog (existence, availability, shop assignment).
 * 5. Item prices, option adjustments, and item subtotals derived strictly from catalog data.
 * 6. Delivery charges derived strictly from authoritative shop document.
 * 7. Subtotal, grandTotal, and totalAmount computed authoritatively on server.
 * 8. Initial status strictly set to 'placed'.
 * 9. Server timestamps and acceptDeadline (+20 min) derived on server.
 * 10. Atomic persistence of final order document in orders/{orderId}.
 * 11. Cost/read efficiency: duplicate menu items in request reuse loaded catalog doc.
 */

const crypto = require("crypto");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

/**
 * Limits for abuse prevention and physical/monetary constraints:
 * - MAX_ITEMS_PER_ORDER: 50 line items. Prevents unbounded array processing / memory DoS.
 * - MAX_ITEM_QUANTITY: 99 per item. Matches Flutter model clamp(1, 99).
 * - MAX_TOTAL_QUANTITY: 500 total units. Prevents physical fulfillment impossibility / inventory denial of service.
 * - MAX_ITEM_PRICE: 100,000 INR (1 Lakh). Matches Flutter model clamp(0, 100000).
 * - MAX_ORDER_GRAND_TOTAL: 500,000 INR (5 Lakhs). Standard payment gateway single-transaction ceiling in India.
 * - MAX_OPTIONS_PER_ITEM: 20 option selections per line item.
 * - MAX_CUSTOMER_NAME_LENGTH: 100 characters.
 * - MAX_CUSTOMER_PHONE_LENGTH: 20 characters.
 * - MAX_SPECIAL_INSTRUCTIONS_LENGTH: 500 characters.
 * - MAX_DELIVERY_NOTE_LENGTH: 200 characters.
 */
const MAX_ITEMS_PER_ORDER = 50;
const MAX_ITEM_QUANTITY = 99;
const MAX_TOTAL_QUANTITY = 500;
const MAX_ITEM_PRICE = 100000;
const MAX_ORDER_GRAND_TOTAL = 500000;

const MAX_OPTIONS_PER_ITEM = 20;
const MAX_CUSTOMER_NAME_LENGTH = 100;
const MAX_CUSTOMER_PHONE_LENGTH = 20;
const MAX_SPECIAL_INSTRUCTIONS_LENGTH = 500;
const MAX_DELIVERY_NOTE_LENGTH = 200;

/**
 * Standard identifier syntax: 1-64 alphanumeric characters, underscores, or hyphens.
 * Syntactic validation only; authoritative existence & tenancy checks remain mandatory.
 */
const ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;

/**
 * Disallowed control characters: null byte (\x00) and unprintable ASCII control characters.
 * Standard whitespace (\t, \n, \r) is permitted.
 */
const CONTROL_CHAR_REGEX = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/;

/**
 * Category A: Prohibited security, identity, and internal privileged fields.
 * Any presence of these keys anywhere in the request results in strict rejection.
 */
const PROHIBITED_SECURITY_KEYS = new Set([
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
  "orderId",
  "allowMissingIdempotencyKey",
  "options",
]);

/**
 * Actual supported production order placement methods.
 * Discovered from Flutter client models (ShopOrderMethod, AppOrder) and test suites.
 */
const ALLOWED_ORDER_METHODS = new Set(["app", "whatsapp", "wa", "in_app", "both"]);

/**
 * Idempotency Key constraints (Phase 4.4):
 * 8-128 alphanumeric characters, underscores, or hyphens.
 */
const IDEMPOTENCY_KEY_REGEX = /^[a-zA-Z0-9_-]{8,128}$/;

/**
 * Rate Limiting Constraints (Phase 4.4):
 * - RATE_LIMIT_USER_MAX: 5 orders per minute per authenticated user.
 * - RATE_LIMIT_USER_WINDOW_MS: 60,000 ms (1 minute).
 * - RATE_LIMIT_USER_BURST_MAX: 3 orders per 10 seconds per authenticated user.
 * - RATE_LIMIT_USER_BURST_WINDOW_MS: 10,000 ms (10 seconds).
 * - RATE_LIMIT_SHOP_MAX: 60 orders per minute aggregate per shop.
 * - RATE_LIMIT_SHOP_WINDOW_MS: 60,000 ms (1 minute).
 */
const RATE_LIMIT_USER_MAX = 5;
const RATE_LIMIT_USER_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_USER_BURST_MAX = 3;
const RATE_LIMIT_USER_BURST_WINDOW_MS = 10 * 1000;
const RATE_LIMIT_SHOP_MAX = 60;
const RATE_LIMIT_SHOP_WINDOW_MS = 60 * 1000;

/**
 * Idempotency Lifecycle Constraints (Phase 4.4):
 * - IDEMPOTENCY_EXPIRY_MS: 24 hours retention period.
 * - IDEMPOTENCY_PENDING_STALE_MS: 30 seconds threshold for stale pending reservation recovery.
 */
const IDEMPOTENCY_EXPIRY_MS = 24 * 60 * 60 * 1000;
const IDEMPOTENCY_PENDING_STALE_MS = 30 * 1000;

/**
 * Derives a deterministic fixed-length (64 hex characters / 256 bits) Firestore document ID
 * for idempotency records, eliminating raw user-input document paths and bounding path length.
 *
 * @param {string} canonicalCustomerUid
 * @param {string} idempotencyKey
 * @returns {string} SHA-256 hexadecimal digest
 */
function computeIdempotencyDocId(canonicalCustomerUid, idempotencyKey) {
  return crypto
    .createHash("sha256")
    .update(`${canonicalCustomerUid}:${idempotencyKey}`)
    .digest("hex");
}

/**
 * Computes a deterministic SHA-256 request fingerprint from canonical business intent fields only.
 * Strictly excludes:
 * - orderId
 * - timestamps (createdAt, updatedAt, acceptDeadline)
 * - client-supplied financial values (subtotal, deliveryCharges, grandTotal, etc.)
 * - server pricing & lifecycle metadata
 *
 * Canonicalizes:
 * - shopId: trimmed string
 * - orderMethod: validated canonical string ("app", "whatsapp", or "both")
 * - specialInstructions: trimmed safe text
 * - deliveryNote: trimmed safe text
 * - items: canonical array sorted by menuItemId, quantity, and sorted selectedOptions (groupId, optionId).
 *
 * @param {object} params
 * @param {string} params.shopId
 * @param {Array} params.items
 * @param {string} [params.specialInstructions]
 * @param {string} [params.deliveryNote]
 * @param {string} [params.orderMethod]
 * @returns {string} SHA-256 hexadecimal fingerprint
 */
function computeRequestFingerprint({
  shopId,
  items,
  specialInstructions = "",
  deliveryNote = "",
  orderMethod = "app",
}) {
  const canonicalItems = (items || []).map((it) => {
    const menuItemId = typeof it.menuItemId === "string" ? it.menuItemId.trim() : "";
    const quantity = Number.isInteger(it.quantity) ? it.quantity : 1;
    const rawOptions = Array.isArray(it.selectedOptions) ? it.selectedOptions : [];
    const sortedOptions = [...rawOptions]
      .map((opt) => ({
        groupId: typeof opt.groupId === "string" ? opt.groupId.trim() : "",
        optionId: typeof opt.optionId === "string" ? opt.optionId.trim() : "",
      }))
      .sort((a, b) => {
        const gComp = a.groupId.localeCompare(b.groupId);
        if (gComp !== 0) return gComp;
        return a.optionId.localeCompare(b.optionId);
      });

    return {
      menuItemId,
      quantity,
      selectedOptions: sortedOptions,
    };
  });

  canonicalItems.sort((a, b) => {
    const mComp = a.menuItemId.localeCompare(b.menuItemId);
    if (mComp !== 0) return mComp;
    const qComp = a.quantity - b.quantity;
    if (qComp !== 0) return qComp;
    return JSON.stringify(a.selectedOptions).localeCompare(JSON.stringify(b.selectedOptions));
  });

  const canonicalIntent = {
    shopId: typeof shopId === "string" ? shopId.trim() : "",
    orderMethod: typeof orderMethod === "string" ? orderMethod.trim().toLowerCase() : "app",
    specialInstructions: typeof specialInstructions === "string" ? specialInstructions.trim() : "",
    deliveryNote: typeof deliveryNote === "string" ? deliveryNote.trim() : "",
    items: canonicalItems,
  };

  return crypto
    .createHash("sha256")
    .update(JSON.stringify(canonicalIntent))
    .digest("hex");
}

/**
 * Validates user-supplied text fields without silent truncation.
 *
 * Policy:
 * - wrong type        -> REJECT
 * - null when invalid -> REJECT
 * - oversized         -> REJECT
 * - invalid/control   -> REJECT
 * - valid string      -> PRESERVE as-is
 *
 * @param {string} fieldName - Field name for error reporting
 * @param {any} value - User supplied value
 * @param {number} maxLength - Maximum allowable string length
 * @returns {string} Preserved string value (empty string if omitted/undefined)
 */
function validateSafeText(fieldName, value, maxLength) {
  if (value === undefined) {
    return "";
  }
  if (value === null) {
    const err = new Error(`Invalid field "${fieldName}": null is not a valid string.`);
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }
  if (typeof value !== "string") {
    const err = new Error(`Invalid field "${fieldName}": expected a string, got ${typeof value}.`);
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }
  if (value.length > maxLength) {
    const err = new Error(
      `Field "${fieldName}" exceeds maximum allowable length of ${maxLength} characters (received ${value.length}).`
    );
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }
  if (CONTROL_CHAR_REGEX.test(value)) {
    const err = new Error(`Field "${fieldName}" contains disallowed control characters or null bytes.`);
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }
  return value;
}

/**
 * Validates orderMethod against actual supported production values.
 *
 * @param {any} rawMethod - User supplied orderMethod
 * @returns {string} Canonical orderMethod string ("app", "whatsapp", or "both")
 */
function validateOrderMethod(rawMethod) {
  if (rawMethod === undefined) {
    return "app";
  }
  if (rawMethod === null || typeof rawMethod !== "string") {
    const err = new Error(`Invalid orderMethod: expected a string, got ${rawMethod === null ? "null" : typeof rawMethod}.`);
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }
  const clean = rawMethod.trim().toLowerCase();
  if (!ALLOWED_ORDER_METHODS.has(clean)) {
    const err = new Error(
      `Invalid orderMethod "${rawMethod}". Allowed values are: ${Array.from(ALLOWED_ORDER_METHODS).join(", ")}.`
    );
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }
  if (clean === "whatsapp" || clean === "wa") return "whatsapp";
  if (clean === "both") return "both";
  return "app";
}

/**
 * Converts INR rupees to integer paise (minor units).
 * Guarantees exact integer arithmetic and eliminates floating point drift.
 *
 * @param {number} rupees
 * @returns {number} integer paise
 */
function toPaise(rupees) {
  if (typeof rupees !== "number" || !Number.isFinite(rupees)) {
    throw new Error(`Invalid monetary amount: ${rupees}`);
  }
  return Math.round(rupees * 100);
}

/**
 * Converts integer paise back to INR rupees (decimal representation).
 *
 * @param {number} paise
 * @returns {number} rupees
 */
function fromPaise(paise) {
  if (!Number.isInteger(paise)) {
    throw new Error(`Expected integer paise amount, got ${paise}`);
  }
  return paise / 100;
}

/**
 * Builds a deterministic cartKey for a menuItem + options combination.
 * Matches Flutter client `CartItem.buildCartKey` sorting logic.
 * 
 * @param {string} menuItemId
 * @param {Array} options
 * @returns {string} deterministic key
 */
function buildDeterministicCartKey(menuItemId, options) {
  if (!options || !Array.isArray(options) || options.length === 0) {
    return menuItemId;
  }
  const sorted = [...options].sort((a, b) => {
    const gComp = (a.groupId || "").localeCompare(b.groupId || "");
    if (gComp !== 0) return gComp;
    return (a.optionId || "").localeCompare(b.optionId || "");
  });
  const tokens = sorted.map((o) => `${o.groupId}:${o.optionId}`).join("|");
  return `${menuItemId}|${tokens}`;
}

/**
 * Validates request input, loads catalog data, enforces atomic rate limits and idempotency,
 * computes authoritative pricing, and atomically persists the verified order document.
 * 
 * @param {FirebaseFirestore.Firestore} db - Firestore instance
 * @param {object} authContext - { uid, token, phone } from verified Firebase Auth
 * @param {object} requestData - untrusted client payload
 * @param {object} [options] - execution options (now, orderId, skipPersistence, allowMissingIdempotencyKey)
 * @returns {Promise<object>} { success: true, orderId, order, isIdempotentReplay? }
 */
async function processServerAuthoritativeOrder(db, authContext, requestData, options = {}) {
  // ─── 1. Authenticate Customer Identity ─────────────────────────────────────
  if (!authContext || typeof authContext.uid !== "string" || authContext.uid.trim().length === 0) {
    const err = new Error("Unauthenticated: Customer authentication is required to place an order.");
    err.code = "unauthenticated";
    err.status = 401;
    throw err;
  }
  const canonicalCustomerId = authContext.uid.trim();

  // ─── 2. Pre-Database Structural & Shape Validation (Phase 4.3 & 4.4) ────────
  // Validates payload structure and data types before touching Firestore,
  // preventing resource exhaustion, type confusion, and injection attacks.

  if (!requestData || typeof requestData !== "object" || Array.isArray(requestData)) {
    const err = new Error("Invalid request payload: expected an object.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  // Category A: Prohibited security & identity fields check at root
  for (const key of Object.keys(requestData)) {
    if (key === "orderId") {
      const err = new Error(
        "Client-supplied orderId is strictly prohibited. Order identity is server-authoritative."
      );
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }
    if (PROHIBITED_SECURITY_KEYS.has(key)) {
      const err = new Error(`Prohibited security/internal field detected: "${key}".`);
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }
  }

  // Customer ID check: Reject spoofed / conflicting customerId
  if (requestData.customerId !== undefined && requestData.customerId !== null) {
    if (typeof requestData.customerId !== "string") {
      const err = new Error("Invalid customerId: expected a string.");
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }
    if (requestData.customerId.trim() !== canonicalCustomerId) {
      const err = new Error(
        `Unauthorized: Conflicting customerId "${requestData.customerId}" does not match authenticated user "${canonicalCustomerId}".`
      );
      err.code = "permission-denied";
      err.status = 403;
      throw err;
    }
  }

  // Validate idempotencyKey (Phase 4.4 Mandatory Correction 2)
  let idempotencyKey = "";
  if (typeof requestData.idempotencyKey === "string" && requestData.idempotencyKey.trim().length > 0) {
    idempotencyKey = requestData.idempotencyKey.trim();
    if (!IDEMPOTENCY_KEY_REGEX.test(idempotencyKey)) {
      const err = new Error(
        `Invalid idempotencyKey format: "${idempotencyKey}". Must be 8-128 alphanumeric characters, underscores, or hyphens.`
      );
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }
  } else {
    // Migration fallback: allowed ONLY if explicitly configured via options.allowMissingIdempotencyKey
    if (options.allowMissingIdempotencyKey === true) {
      idempotencyKey = `legacy_${crypto.randomBytes(8).toString("hex")}`;
    } else {
      const err = new Error(
        "Invalid request: idempotencyKey is required (must be 8-128 alphanumeric characters, underscores, or hyphens)."
      );
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }
  }

  // Validate shopId syntax and length
  if (typeof requestData.shopId !== "string") {
    const err = new Error("Invalid request: shopId is required.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }
  const shopId = requestData.shopId.trim();
  if (!shopId) {
    const err = new Error("Invalid request: shopId cannot be empty.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }
  if (shopId.length > 64 || !ID_REGEX.test(shopId)) {
    const err = new Error(`Invalid shopId format: "${shopId}". Must be 1-64 alphanumeric characters, underscores, or hyphens.`);
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  // Validate orderMethod against actual supported production values
  const validatedOrderMethod = validateOrderMethod(requestData.orderMethod);

  // Validate User Text fields without silent truncation
  const validatedCustomerName = validateSafeText("customerName", requestData.customerName, MAX_CUSTOMER_NAME_LENGTH);
  const validatedCustomerPhone = validateSafeText("customerPhone", requestData.customerPhone, MAX_CUSTOMER_PHONE_LENGTH);
  const validatedSpecialInstructions = validateSafeText("specialInstructions", requestData.specialInstructions, MAX_SPECIAL_INSTRUCTIONS_LENGTH);
  const validatedDeliveryNote = validateSafeText("deliveryNote", requestData.deliveryNote, MAX_DELIVERY_NOTE_LENGTH);

  // Validate items array structure before database reads
  const rawItems = requestData.items;
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    const err = new Error("Invalid request: items must be a non-empty array.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  if (rawItems.length > MAX_ITEMS_PER_ORDER) {
    const err = new Error(
      `Invalid request: Order cannot contain more than ${MAX_ITEMS_PER_ORDER} distinct items (received ${rawItems.length}).`
    );
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  // Validate each item and nested options structurally
  for (let idx = 0; idx < rawItems.length; idx++) {
    const it = rawItems[idx];
    if (!it || typeof it !== "object" || Array.isArray(it)) {
      const err = new Error(`Invalid item payload at index ${idx}: expected an object.`);
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    // Check prohibited keys inside item payload
    for (const k of Object.keys(it)) {
      if (PROHIBITED_SECURITY_KEYS.has(k)) {
        const err = new Error(`Prohibited field "${k}" detected in item at index ${idx}.`);
        err.code = "invalid-argument";
        err.status = 400;
        throw err;
      }
    }

    if (typeof it.menuItemId !== "string") {
      const err = new Error(`Invalid request: Each item must specify a valid menuItemId (item at index ${idx}).`);
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }
    const mId = it.menuItemId.trim();
    if (!mId) {
      const err = new Error("Invalid request: Each item must specify a valid menuItemId.");
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }
    if (mId.length > 64 || !ID_REGEX.test(mId)) {
      const err = new Error(`Invalid menuItemId format at index ${idx}: "${mId}".`);
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    // Validate item quantity: integer between 1 and MAX_ITEM_QUANTITY (99)
    const q = it.quantity;
    if (typeof q !== "number" || !Number.isInteger(q) || q < 1 || q > MAX_ITEM_QUANTITY) {
      const err = new Error(
        `Invalid quantity "${q}" for item "${mId}". Quantity must be an integer between 1 and ${MAX_ITEM_QUANTITY}.`
      );
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    // Validate selectedOptions structure if present
    if (it.selectedOptions !== undefined && it.selectedOptions !== null) {
      if (!Array.isArray(it.selectedOptions)) {
        const err = new Error(`Invalid selectedOptions for item "${mId}": expected an array.`);
        err.code = "invalid-argument";
        err.status = 400;
        throw err;
      }
      if (it.selectedOptions.length > MAX_OPTIONS_PER_ITEM) {
        const err = new Error(
          `Too many selectedOptions for item "${mId}": maximum allowed is ${MAX_OPTIONS_PER_ITEM}, received ${it.selectedOptions.length}.`
        );
        err.code = "invalid-argument";
        err.status = 400;
        throw err;
      }
      for (let optIdx = 0; optIdx < it.selectedOptions.length; optIdx++) {
        const opt = it.selectedOptions[optIdx];
        if (!opt || typeof opt !== "object" || Array.isArray(opt)) {
          const err = new Error(`Malformed selectedOption entry at item "${mId}" option index ${optIdx}.`);
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }
        for (const k of Object.keys(opt)) {
          if (PROHIBITED_SECURITY_KEYS.has(k)) {
            const err = new Error(`Prohibited field "${k}" detected in option at item "${mId}" index ${optIdx}.`);
            err.code = "invalid-argument";
            err.status = 400;
            throw err;
          }
        }
        if (typeof opt.groupId !== "string" || !opt.groupId.trim()) {
          const err = new Error("Each selectedOption must contain valid groupId and optionId.");
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }
        const gId = opt.groupId.trim();
        if (gId.length > 64 || !ID_REGEX.test(gId)) {
          const err = new Error(`Invalid groupId format in selectedOption for item "${mId}": "${gId}".`);
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }
        if (typeof opt.optionId !== "string" || !opt.optionId.trim()) {
          const err = new Error("Each selectedOption must contain valid groupId and optionId.");
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }
        const oId = opt.optionId.trim();
        if (oId.length > 64 || !ID_REGEX.test(oId)) {
          const err = new Error(`Invalid optionId format in selectedOption for item "${mId}": "${oId}".`);
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }
      }
    }
  }

  // ─── 3. Deterministic Idempotency Document ID & Request Fingerprint (Phase 4.4) ─
  const idempotencyDocId = computeIdempotencyDocId(canonicalCustomerId, idempotencyKey);
  const requestFingerprint = computeRequestFingerprint({
    shopId,
    items: rawItems,
    specialInstructions: validatedSpecialInstructions,
    deliveryNote: validatedDeliveryNote,
    orderMethod: validatedOrderMethod,
  });

  const idempDocRef = db.collection("idempotency").doc(idempotencyDocId);

  // ─── 4. Replay Check BEFORE Rate-Limit Consumption (Mandatory Correction 6) ───
  // Resolves an existing completed idempotent attempt before touching rate limits,
  // preventing network retries from consuming user quota or being blocked.
  const existingIdempSnap = await idempDocRef.get();
  const now = options.now instanceof Date ? options.now : new Date();
  const nowMs = now.getTime();

  if (existingIdempSnap.exists) {
    const record = existingIdempSnap.data() || {};
    if (record.status === "completed") {
      if (record.requestFingerprint === requestFingerprint) {
        // MATCH: Idempotent Replay! Return existing order without consuming quota.
        let existingOrder = null;
        if (record.orderId) {
          try {
            const orderSnap = await db.collection("orders").doc(record.orderId).get();
            if (orderSnap.exists) {
              existingOrder = orderSnap.data();
            }
          } catch (_) {}
        }
        return {
          success: true,
          orderId: record.orderId,
          order: existingOrder || record.orderSummary || {},
          isIdempotentReplay: true,
        };
      } else {
        // CONFLICT: Same key reused with different request payload
        const err = new Error(
          `Idempotency conflict: key "${idempotencyKey}" was previously completed with different order parameters.`
        );
        err.code = "failed-precondition";
        err.status = 409;
        throw err;
      }
    } else if (record.status === "pending") {
      const recordCreatedMs = record.createdAt
        ? (typeof record.createdAt.toMillis === "function"
            ? record.createdAt.toMillis()
            : (record.createdAt instanceof Date
                ? record.createdAt.getTime()
                : (typeof record.createdAt === "number" ? record.createdAt : 0)))
        : 0;
      const isStale = (nowMs - recordCreatedMs) >= IDEMPOTENCY_PENDING_STALE_MS;

      if (!isStale) {
        if (record.requestFingerprint === requestFingerprint) {
          const err = new Error(
            `Order with idempotencyKey "${idempotencyKey}" is currently being processed. Please retry shortly.`
          );
          err.code = "failed-precondition";
          err.status = 409;
          throw err;
        } else {
          const err = new Error(
            `Idempotency conflict: key "${idempotencyKey}" is currently pending for a different order payload.`
          );
          err.code = "failed-precondition";
          err.status = 409;
          throw err;
        }
      }
      // If stale, safely reclaim inside transaction below.
    }
  }

  // ─── 5. Atomic Reservation, Rate Limiting & Order Persistence (Mandatory Corrections 1 & 5) ─
  const userRateLimitRef = db.collection("_rateLimits").doc(`user_${canonicalCustomerId}`);
  const shopRateLimitRef = db.collection("_rateLimits").doc(`shop_${shopId}`);
  const shopDocRef = db.collection("shops").doc(shopId);

  const uniqueItemIds = [...new Set(rawItems.map((it) => it.menuItemId.trim()))];
  const itemRefs = uniqueItemIds.map((mId) =>
    db.collection("shops").doc(shopId).collection("menuItems").doc(mId)
  );
  const userDocRef = db.collection("users").doc(canonicalCustomerId);

  // Derive orderId before transaction read phase so order collision can be tested atomically
  let orderId;
  if (typeof options._serverOrderId === "string" && options._serverOrderId.trim().length > 0) {
    orderId = options._serverOrderId.trim();
  } else {
    const randomHex = crypto.randomBytes(6).toString("hex").toUpperCase();
    orderId = `ORD_${nowMs}_${randomHex}`;
  }
  const orderRef = db.collection("orders").doc(orderId);

  const executeOrderCreationTransaction = async (t) => {
    // ─── Phase A: Transactional Reads (ALL reads before ANY writes) ───────────
    // 1. Check idempotency record inside transaction to serialize concurrent attempts
    const txIdempSnap = await t.get(idempDocRef);
    if (txIdempSnap.exists) {
      const txRecord = txIdempSnap.data() || {};
      if (txRecord.status === "completed") {
        if (txRecord.requestFingerprint === requestFingerprint) {
          return {
            isReplay: true,
            orderId: txRecord.orderId,
            orderSummary: txRecord.orderSummary,
          };
        } else {
          const err = new Error(
            `Idempotency conflict: key "${idempotencyKey}" was previously completed with different order parameters.`
          );
          err.code = "failed-precondition";
          err.status = 409;
          throw err;
        }
      } else if (txRecord.status === "pending") {
        const txCreatedMs = txRecord.createdAt
          ? (typeof txRecord.createdAt.toMillis === "function"
              ? txRecord.createdAt.toMillis()
              : (txRecord.createdAt instanceof Date
                  ? txRecord.createdAt.getTime()
                  : (typeof txRecord.createdAt === "number" ? txRecord.createdAt : 0)))
          : 0;
        const isTxStale = (nowMs - txCreatedMs) >= IDEMPOTENCY_PENDING_STALE_MS;
        if (!isTxStale) {
          const err = new Error(
            `Order with idempotencyKey "${idempotencyKey}" is currently being processed. Please retry shortly.`
          );
          err.code = "failed-precondition";
          err.status = 409;
          throw err;
        }
      }
    }

    // 2. Read order document to prevent collisions
    const existingOrderSnap = await t.get(orderRef);
    if (existingOrderSnap.exists) {
      const err = new Error(`Order collision: document with ID "${orderId}" already exists. Overwrite prohibited.`);
      err.code = "already-exists";
      err.status = 409;
      throw err;
    }

    // 3. Read rate limits inside transaction (Atomic protection against read-then-write race)
    const [userLimitSnap, shopLimitSnap, shopDoc, ...itemDocs] = await Promise.all([
      t.get(userRateLimitRef),
      t.get(shopRateLimitRef),
      t.get(shopDocRef),
      ...itemRefs.map((ref) => t.get(ref)),
    ]);

    let userDoc = null;
    try {
      userDoc = await t.get(userDocRef);
    } catch (_) {}

    const catalogItemDocs = new Map();
    uniqueItemIds.forEach((mId, i) => {
      catalogItemDocs.set(mId, itemDocs[i]);
    });

    // ─── Phase B: In-Memory Validation & Calculation ──────────────────────────
    // 1. Evaluate User Rate Limits
    const userData = userLimitSnap && userLimitSnap.exists ? userLimitSnap.data() || {} : {};
    const rawUserTimestamps = Array.isArray(userData.recentOrders) ? userData.recentOrders : [];
    const activeUserTimestamps = rawUserTimestamps.filter(
      (ts) => typeof ts === "number" && (nowMs - ts) < RATE_LIMIT_USER_WINDOW_MS
    );
    const burstTimestamps = activeUserTimestamps.filter(
      (ts) => (nowMs - ts) < RATE_LIMIT_USER_BURST_WINDOW_MS
    );
    if (burstTimestamps.length >= RATE_LIMIT_USER_BURST_MAX) {
      const err = new Error(
        `Rate limit exceeded: Maximum ${RATE_LIMIT_USER_BURST_MAX} orders per 10 seconds. Please wait before placing another order.`
      );
      err.code = "resource-exhausted";
      err.status = 429;
      throw err;
    }
    if (activeUserTimestamps.length >= RATE_LIMIT_USER_MAX) {
      const err = new Error(
        `Rate limit exceeded: Maximum ${RATE_LIMIT_USER_MAX} orders per minute. Please wait before placing another order.`
      );
      err.code = "resource-exhausted";
      err.status = 429;
      throw err;
    }

    // 2. Evaluate Shop Rate Limits
    const shopLimitData = shopLimitSnap && shopLimitSnap.exists ? shopLimitSnap.data() || {} : {};
    const rawShopTimestamps = Array.isArray(shopLimitData.recentOrders) ? shopLimitData.recentOrders : [];
    const activeShopTimestamps = rawShopTimestamps.filter(
      (ts) => typeof ts === "number" && (nowMs - ts) < RATE_LIMIT_SHOP_WINDOW_MS
    );
    if (activeShopTimestamps.length >= RATE_LIMIT_SHOP_MAX) {
      const err = new Error(
        `Shop rate limit exceeded: Shop "${shopId}" is currently experiencing peak order volume (${RATE_LIMIT_SHOP_MAX} orders/min). Please try again shortly.`
      );
      err.code = "resource-exhausted";
      err.status = 429;
      throw err;
    }

    // 3. Validate Shop Existence and Status
    if (!shopDoc || !shopDoc.exists) {
      const err = new Error(`Shop with ID "${shopId}" does not exist.`);
      err.code = "not-found";
      err.status = 404;
      throw err;
    }

    const shopData = shopDoc.data() || {};
    if (shopData.isActive === false) {
      const err = new Error(`Shop "${shopData.name || shopId}" is currently inactive/closed.`);
      err.code = "failed-precondition";
      err.status = 400;
      throw err;
    }

    const authoritativeShopName = shopData.name || "Shop";
    const rawDelivery = typeof shopData.deliveryCharges === "number"
      ? shopData.deliveryCharges
      : (typeof shopData.delivery_charges === "number" ? shopData.delivery_charges : (shopData.deliveryCharges ?? shopData.delivery_charges ?? 0));

    if (typeof rawDelivery !== "number" || !Number.isFinite(rawDelivery) || rawDelivery < 0) {
      const err = new Error(`Catalog error: Shop "${shopId}" has invalid or negative delivery charges (${rawDelivery}).`);
      err.code = "failed-precondition";
      err.status = 400;
      throw err;
    }
    const deliveryChargesPaise = toPaise(rawDelivery);
    const authoritativeDeliveryCharges = fromPaise(deliveryChargesPaise);

    // 4. Process Each Item with Authoritative Catalog & Option Pricing
    const processedItems = [];
    let totalItemCount = 0;
    let calculatedSubtotalPaise = 0;

    for (let idx = 0; idx < rawItems.length; idx++) {
      const reqItem = rawItems[idx];
      const menuItemId = typeof reqItem.menuItemId === "string" ? reqItem.menuItemId.trim() : "";
      const quantity = reqItem.quantity;

      const docSnap = catalogItemDocs.get(menuItemId);
      if (!docSnap || !docSnap.exists) {
        const err = new Error(`Menu item "${menuItemId}" not found in shop "${shopId}".`);
        err.code = "not-found";
        err.status = 404;
        throw err;
      }

      const menuData = docSnap.data() || {};

      // Validate shop tenancy
      if (menuData.shopId && menuData.shopId !== shopId) {
        const err = new Error(`Menu item "${menuItemId}" does not belong to shop "${shopId}".`);
        err.code = "failed-precondition";
        err.status = 400;
        throw err;
      }

      // Validate availability
      if (menuData.isAvailable === false) {
        const err = new Error(`Menu item "${menuData.name || menuItemId}" is currently out of stock / unavailable.`);
        err.code = "failed-precondition";
        err.status = 400;
        throw err;
      }

      // Validate authoritative base catalog price
      const rawBasePrice = menuData.price;
      if (typeof rawBasePrice !== "number" || !Number.isFinite(rawBasePrice) || rawBasePrice < 0) {
        const err = new Error(`Catalog error: Menu item "${menuItemId}" has invalid or negative price (${rawBasePrice}).`);
        err.code = "failed-precondition";
        err.status = 400;
        throw err;
      }
      const basePricePaise = toPaise(rawBasePrice);

      let startingPricePaise = 0;
      if (menuData.startingPrice !== undefined && menuData.startingPrice !== null) {
        if (typeof menuData.startingPrice !== "number" || !Number.isFinite(menuData.startingPrice) || menuData.startingPrice < 0) {
          const err = new Error(`Catalog error: Menu item "${menuItemId}" has invalid startingPrice (${menuData.startingPrice}).`);
          err.code = "failed-precondition";
          err.status = 400;
          throw err;
        }
        startingPricePaise = toPaise(menuData.startingPrice);
      }

      // Compute Authoritative Unit Price and Options
      let unitPricePaise = 0;
      let hasAnyFixed = false;
      const authoritativeSelectedOptions = [];
      const optionsDescriptionTokens = [];

      const reqOptions = Array.isArray(reqItem.selectedOptions) ? reqItem.selectedOptions : [];
      const catalogOptionGroups = Array.isArray(menuData.optionGroups)
        ? menuData.optionGroups
        : (Array.isArray(menuData.groups) ? menuData.groups : []);

      if (catalogOptionGroups.length === 0 && reqOptions.length > 0) {
        const err = new Error(`Menu item "${menuItemId}" does not accept option selections.`);
        err.code = "invalid-argument";
        err.status = 400;
        throw err;
      }

      if (catalogOptionGroups.length > 0) {
        const selectionsByGroup = new Map();
        const seenOptionKeys = new Set();

        for (const reqOpt of reqOptions) {
          const groupId = typeof reqOpt.groupId === "string" ? reqOpt.groupId.trim() : "";
          const optionId = typeof reqOpt.optionId === "string" ? reqOpt.optionId.trim() : "";

          const group = catalogOptionGroups.find((g) => g.id === groupId);
          if (!group) {
            const err = new Error(`Invalid option group "${groupId}" does not exist for menu item "${menuItemId}".`);
            err.code = "invalid-argument";
            err.status = 400;
            throw err;
          }

          const catalogOpt = (group.options || []).find((o) => o.id === optionId);
          if (!catalogOpt) {
            const err = new Error(`Invalid option "${optionId}" does not exist in group "${groupId}" for item "${menuItemId}".`);
            err.code = "invalid-argument";
            err.status = 400;
            throw err;
          }

          const optKey = `${groupId}:${optionId}`;
          if (seenOptionKeys.has(optKey)) {
            const err = new Error(`Duplicate selection of option "${optionId}" in group "${groupId}".`);
            err.code = "invalid-argument";
            err.status = 400;
            throw err;
          }
          seenOptionKeys.add(optKey);

          const pricingType = catalogOpt.pricingType || (group.groupType === "fixed" ? "fixedPrice" : "priceAdjustment");
          let catalogOptPricePaise = 0;

          if (pricingType !== "selectionOnly") {
            const rawOptPrice = catalogOpt.price;
            if (typeof rawOptPrice !== "number" || !Number.isFinite(rawOptPrice) || rawOptPrice < 0) {
              const err = new Error(
                `Catalog error: Option "${optionId}" in group "${groupId}" has invalid or negative price (${rawOptPrice}).`
              );
              err.code = "failed-precondition";
              err.status = 400;
              throw err;
            }
            catalogOptPricePaise = toPaise(rawOptPrice);
          }

          if (!selectionsByGroup.has(groupId)) {
            selectionsByGroup.set(groupId, []);
          }
          selectionsByGroup.get(groupId).push({
            group,
            catalogOpt,
            pricingType,
            catalogOptPricePaise,
          });
        }

        // Validate group-level selection constraints
        for (const group of catalogOptionGroups) {
          const selections = selectionsByGroup.get(group.id) || [];
          const count = selections.length;

          const isMulti = group.multiple === true || group.allowMultiple === true || (typeof group.maxSelections === "number" && group.maxSelections > 1);

          let minSelections;
          let maxSelections;

          if (typeof group.minSelections === "number") {
            minSelections = group.minSelections;
          } else if (group.required === true || group.groupType === "fixed") {
            minSelections = 1;
          } else {
            minSelections = 0;
          }

          if (typeof group.maxSelections === "number") {
            maxSelections = group.maxSelections;
          } else if (isMulti) {
            maxSelections = Array.isArray(group.options) ? group.options.length : 10;
          } else {
            maxSelections = 1;
          }

          if (count < minSelections) {
            const err = new Error(
              `Missing required option selection for group "${group.name || group.id}". Expected at least ${minSelections}, got ${count}.`
            );
            err.code = "invalid-argument";
            err.status = 400;
            throw err;
          }

          if (count > maxSelections) {
            const err = new Error(
              `Too many options selected for group "${group.name || group.id}". Maximum allowed is ${maxSelections}, got ${count}.`
            );
            err.code = "invalid-argument";
            err.status = 400;
            throw err;
          }

          for (const sel of selections) {
            if (group.groupType === "fixed" || sel.pricingType === "fixedPrice") {
              hasAnyFixed = true;
            }
            unitPricePaise += sel.catalogOptPricePaise;

            authoritativeSelectedOptions.push({
              groupId: group.id,
              groupName: group.name || "",
              optionId: sel.catalogOpt.id,
              optionName: sel.catalogOpt.name || "",
              pricingType: sel.pricingType,
              price: fromPaise(sel.catalogOptPricePaise),
            });

            if (sel.catalogOpt.name) {
              optionsDescriptionTokens.push(sel.catalogOpt.name);
            }
          }
        }

        if (!hasAnyFixed) {
          unitPricePaise += basePricePaise;
        }

        if (unitPricePaise <= 0) {
          unitPricePaise = startingPricePaise > 0 ? startingPricePaise : basePricePaise;
        }
      } else {
        unitPricePaise = basePricePaise;
      }

      if (unitPricePaise > toPaise(MAX_ITEM_PRICE)) {
        const err = new Error(
          `Item unit price for "${menuItemId}" (₹${fromPaise(unitPricePaise)}) exceeds allowable maximum limit of ₹${MAX_ITEM_PRICE}.`
        );
        err.code = "invalid-argument";
        err.status = 400;
        throw err;
      }

      const itemSubtotalPaise = unitPricePaise * quantity;
      calculatedSubtotalPaise += itemSubtotalPaise;
      totalItemCount += quantity;

      processedItems.push({
        itemId: menuItemId,
        menuItemId: menuItemId,
        name: menuData.name || "Item",
        price: fromPaise(unitPricePaise),
        quantity: quantity,
        subtotal: fromPaise(itemSubtotalPaise),
        imageUrl: menuData.imageUrl || "",
        optionsDescription: optionsDescriptionTokens.join(" · "),
        selectedOptions: authoritativeSelectedOptions,
        cartKey: buildDeterministicCartKey(menuItemId, authoritativeSelectedOptions),
      });
    }

    if (totalItemCount > MAX_TOTAL_QUANTITY) {
      const err = new Error(
        `Total item quantity across all order items (${totalItemCount}) exceeds allowable limit of ${MAX_TOTAL_QUANTITY}.`
      );
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    const grandTotalPaise = calculatedSubtotalPaise + deliveryChargesPaise;
    if (grandTotalPaise > toPaise(MAX_ORDER_GRAND_TOTAL)) {
      const err = new Error(
        `Order grand total (₹${fromPaise(grandTotalPaise)}) exceeds allowable maximum limit of ₹${MAX_ORDER_GRAND_TOTAL}.`
      );
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    const calculatedSubtotal = fromPaise(calculatedSubtotalPaise);
    const grandTotal = fromPaise(grandTotalPaise);
    const totalAmount = grandTotal;

    // 5. Derive Customer Details
    let customerName = "Student";
    let customerPhone = "";

    if (authContext.token && typeof authContext.token.phone_number === "string") {
      customerPhone = authContext.token.phone_number;
    } else if (typeof authContext.phone === "string") {
      customerPhone = authContext.phone;
    }

    if (userDoc && userDoc.exists) {
      const userData = userDoc.data() || {};
      if (userData.name && typeof userData.name === "string" && userData.name.trim().length > 0) {
        customerName = userData.name.trim();
      }
      if (userData.phone && typeof userData.phone === "string" && userData.phone.trim().length > 0) {
        customerPhone = userData.phone.trim();
      }
    }

    if (customerName === "Student" && validatedCustomerName.length > 0) {
      customerName = validatedCustomerName;
    }
    if (!customerPhone && validatedCustomerPhone.length > 0) {
      customerPhone = validatedCustomerPhone;
    }

    const specialInstructions = validatedSpecialInstructions;
    const deliveryNote = validatedDeliveryNote.length > 0
      ? validatedDeliveryNote
      : (shopData.deliveryNote || "Bennett University");

    const orderMethod = validatedOrderMethod;

    // 6. Timestamps and Lifecycle Deadlines
    const acceptDeadlineDate = new Date(now.getTime() + 20 * 60 * 1000); // 20 minutes
    const createdAtTimestamp = options.now ? Timestamp.fromDate(now) : FieldValue.serverTimestamp();
    const updatedAtTimestamp = options.now ? Timestamp.fromDate(now) : FieldValue.serverTimestamp();

    const finalOrderDoc = {
      orderId,
      shopId,
      shopName: authoritativeShopName,
      customerId: canonicalCustomerId,
      customerName,
      customerPhone,
      items: processedItems,
      subtotal: calculatedSubtotal,
      deliveryCharges: authoritativeDeliveryCharges,
      totalItems: totalItemCount,
      grandTotal: grandTotal,
      totalAmount: totalAmount,
      specialInstructions,
      deliveryNote,
      status: "placed",
      rejectionReason: "",
      orderMethod,
      createdAt: createdAtTimestamp,
      updatedAt: updatedAtTimestamp,
      acceptDeadline: Timestamp.fromDate(acceptDeadlineDate),
    };

    // ─── Phase C: Transactional Writes (Atomic persistence) ────────────────────
    if (options.skipPersistence !== true) {
      t.set(orderRef, finalOrderDoc);

      const idempotencyDoc = {
        uid: canonicalCustomerId,
        idempotencyKey,
        requestFingerprint,
        status: "completed",
        orderId,
        createdAt: createdAtTimestamp,
        expiresAt: Timestamp.fromDate(new Date(now.getTime() + IDEMPOTENCY_EXPIRY_MS)),
        orderSummary: {
          orderId,
          shopId,
          grandTotal: finalOrderDoc.grandTotal,
          status: finalOrderDoc.status,
        },
      };
      t.set(idempDocRef, idempotencyDoc);

      // Atomic Rate-limit state updates
      const updatedUserTimestamps = [...activeUserTimestamps, nowMs];
      t.set(userRateLimitRef, {
        uid: canonicalCustomerId,
        recentOrders: updatedUserTimestamps,
        updatedAt: updatedAtTimestamp,
      });

      const updatedShopTimestamps = [...activeShopTimestamps, nowMs];
      t.set(shopRateLimitRef, {
        shopId,
        recentOrders: updatedShopTimestamps,
        updatedAt: updatedAtTimestamp,
      });
    }

    return {
      isReplay: false,
      orderId,
      order: finalOrderDoc,
    };
  };

  let txResult;
  if (typeof db.runTransaction === "function") {
    txResult = await db.runTransaction(executeOrderCreationTransaction);
  } else {
    // Non-transactional fallback for minimal stub mocks
    const mockTx = {
      get: async (ref) => ref.get(),
      set: async (ref, data) => ref.set(data),
      create: async (ref, data) => (typeof ref.create === "function" ? ref.create(data) : ref.set(data)),
    };
    txResult = await executeOrderCreationTransaction(mockTx);
  }

  if (txResult && txResult.isReplay) {
    let existingOrder = null;
    if (txResult.orderId) {
      try {
        const orderSnap = await db.collection("orders").doc(txResult.orderId).get();
        if (orderSnap.exists) {
          existingOrder = orderSnap.data();
        }
      } catch (_) {}
    }
    return {
      success: true,
      orderId: txResult.orderId,
      order: existingOrder || txResult.orderSummary || {},
      isIdempotentReplay: true,
    };
  }

  return {
    success: true,
    orderId: txResult.orderId,
    order: txResult.order,
  };
}

module.exports = {
  processServerAuthoritativeOrder,
  buildDeterministicCartKey,
  computeIdempotencyDocId,
  computeRequestFingerprint,
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
  IDEMPOTENCY_KEY_REGEX,
  RATE_LIMIT_USER_MAX,
  RATE_LIMIT_USER_WINDOW_MS,
  RATE_LIMIT_USER_BURST_MAX,
  RATE_LIMIT_USER_BURST_WINDOW_MS,
  RATE_LIMIT_SHOP_MAX,
  RATE_LIMIT_SHOP_WINDOW_MS,
  IDEMPOTENCY_EXPIRY_MS,
  IDEMPOTENCY_PENDING_STALE_MS,
};
