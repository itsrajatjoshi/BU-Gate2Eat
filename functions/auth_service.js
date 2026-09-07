/**
 * YummBU — Server-Side Authentication & Role Claims Service
 * 
 * Responsibilities:
 * 1. Authoritative canonical phone normalization and validation.
 * 2. Authoritative server-side role resolution (admin, shopkeeper, customer).
 * 3. Authoritative server-side shopId and customerId scoping.
 * 4. Deterministic UID generation (phone_<cleanPhone>).
 * 5. Server-trusted custom claims creation (role, shopId, customerId).
 * 6. Firebase Custom Token minting via Firebase Admin SDK.
 * 
 * SECURITY INVARIANTS:
 * - Client parameters for role, shopId, customerId, or claims are STRICTLY REJECTED.
 * - All claims are determined entirely on the backend based on verified phone numbers.
 * - Admin credentials / service account keys are NEVER bundled or exposed to Flutter.
 */

const { getAuth } = require("firebase-admin/auth");

// ─── Authoritative Server-Side Mappings ─────────────────────────────────────
// The backend is the single source of truth for administrative and vendor access.
const SERVER_ADMIN_PHONES = Object.freeze(["8078643910"]);

const SERVER_SHOPKEEPER_PHONE_MAP = Object.freeze({
  "8000383993": "rajat_shop",
  "8295643910": "nayan_shop",
  "8875344034": "kivisha_shop",
  "8079065843": "up16_junction_fast_food",
  "8745007244": "up16_junction_fast_food",
  "8745950335": "up16_junction_fast_food",
  "8888822222": "raja_hotel",
  "9999922222": "up16_coffee_queen",
});

const SHOP_ALIASES = Object.freeze({
  "up16_queens": "up16_coffee_queen",
});

// ─── Canonical RBAC Role & Status Definitions (Checkpoint 2.1) ─────────────
const CANONICAL_ROLES = Object.freeze(["customer", "shopkeeper", "admin"]);
const CANONICAL_ACCOUNT_STATUSES = Object.freeze(["active", "deactivated"]);

/**
 * Validates and constructs a minimal, server-trusted custom claims object.
 * 
 * Invariants:
 * - Role must be one of: "customer", "shopkeeper", "admin".
 * - "admin" claims strictly omit shopId (admin has platform-wide authority).
 * - "shopkeeper" claims strictly require a valid, non-empty canonical shopId.
 * - "customer" claims omit shopId.
 * 
 * @param {string} role - canonical role
 * @param {object} [options] - additional attributes (shopId, customerId, status)
 * @returns {object} frozen minimal claims object
 */
function buildCanonicalClaims(role, options = {}) {
  if (!role || typeof role !== "string") {
    throw new Error("Invalid role input: role must be a non-empty string.");
  }
  const cleanRole = role.toLowerCase().trim();
  if (!CANONICAL_ROLES.includes(cleanRole)) {
    throw new Error(`Invalid canonical role: "${role}". Must be one of: ${CANONICAL_ROLES.join(", ")}`);
  }

  if (cleanRole === "admin") {
    const claims = { role: "admin" };
    if (options.status && CANONICAL_ACCOUNT_STATUSES.includes(options.status)) {
      claims.status = options.status;
    }
    return Object.freeze(claims);
  }

  if (cleanRole === "shopkeeper") {
    const rawShopId = options.shopId;
    const canonicalShopId = canonicalizeShopId(rawShopId);
    if (!canonicalShopId || typeof canonicalShopId !== "string") {
      throw new Error("Shopkeeper role strictly requires a valid, authoritative shopId assignment.");
    }
    const claims = {
      role: "shopkeeper",
      shopId: canonicalShopId,
    };
    if (options.status && CANONICAL_ACCOUNT_STATUSES.includes(options.status)) {
      claims.status = options.status;
    }
    return Object.freeze(claims);
  }

  // Customer
  const claims = { role: "customer" };
  if (options.customerId && typeof options.customerId === "string") {
    claims.customerId = options.customerId;
  }
  if (options.status && CANONICAL_ACCOUNT_STATUSES.includes(options.status)) {
    claims.status = options.status;
  }
  return Object.freeze(claims);
}

/**
 * Normalizes and validates a phone number into a canonical 10-digit string.
 * Strips non-digits, international prefix (+91 / 91), and trunk zero (0).
 * 
 * @param {string} rawPhone
 * @returns {string} 10-digit canonical phone number
 * @throws {Error} if phone is null, not a string, or invalid length/format
 */
function normalizeCanonicalPhone(rawPhone) {
  if (!rawPhone || typeof rawPhone !== "string") {
    throw new Error("Invalid phone input: phone must be a non-empty string.");
  }
  let digits = rawPhone.replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("91")) {
    digits = digits.substring(2);
  }
  if (digits.length === 11 && digits.startsWith("0")) {
    digits = digits.substring(1);
  }
  if (!/^[0-9]{10}$/.test(digits)) {
    throw new Error(`Malformed phone number: "${rawPhone}". Must be a valid 10-digit Indian mobile number.`);
  }
  return digits;
}

/**
 * Resolves alias shop IDs to the authoritative canonical Firestore shop ID.
 * 
 * @param {string} shopId
 * @returns {string} canonical shop ID
 */
function canonicalizeShopId(shopId) {
  if (!shopId) return null;
  return SHOP_ALIASES[shopId] || shopId;
}

/**
 * Authoritative Server-Side Role and Identity Resolver.
 * Maps a canonical 10-digit phone number to:
 * - role: "admin" | "shopkeeper" | "customer"
 * - uid: "phone_<cleanPhone>" (Deterministic Firebase Auth UID)
 * - customerId: "cust_<cleanPhone>" (only for customer)
 * - shopId: canonicalShopId (only for shopkeeper)
 * - claims: minimal server-trusted custom claims object
 * 
 * @param {string} canonicalPhone
 * @returns {object} resolved identity metadata
 */
function resolveIdentityForPhone(canonicalPhone) {
  const cleanPhone = normalizeCanonicalPhone(canonicalPhone);
  const uid = `phone_${cleanPhone}`;

  // 1. Admin check
  if (SERVER_ADMIN_PHONES.includes(cleanPhone)) {
    return {
      role: "admin",
      phone: cleanPhone,
      uid,
      claims: buildCanonicalClaims("admin"),
    };
  }

  // 2. Shopkeeper check
  if (SERVER_SHOPKEEPER_PHONE_MAP[cleanPhone]) {
    const rawShopId = SERVER_SHOPKEEPER_PHONE_MAP[cleanPhone];
    const canonicalShopId = canonicalizeShopId(rawShopId);
    return {
      role: "shopkeeper",
      phone: cleanPhone,
      shopId: canonicalShopId,
      uid,
      claims: buildCanonicalClaims("shopkeeper", { shopId: canonicalShopId }),
    };
  }

  // 3. Customer (Default for all registered user phones)
  const customerId = `cust_${cleanPhone}`;
  return {
    role: "customer",
    phone: cleanPhone,
    customerId,
    uid,
    claims: buildCanonicalClaims("customer", { customerId }),
  };
}

/**
 * Server-Side Custom Token Minting Service.
 * 
 * Enforces strict security boundary:
 * - Reject any client-supplied role, shopId, or claims.
 * - Resolves identity strictly via resolveIdentityForPhone().
 * - Creates/gets the user with deterministic UID: phone_<cleanPhone>.
 * - Sets server-trusted custom user claims.
 * - Mints Firebase custom token via Admin SDK.
 * 
 * @param {string} phone - Canonical mobile number
 * @param {object} [options] - Testing options (e.g. injected authInstance)
 * @returns {Promise<{customToken: string, uid: string, role: string, customerId?: string, shopId?: string}>}
 */
async function createCustomTokenForPhone(phone, options = {}) {
  // STRICT SECURITY GUARD: Reject any client attempt to override server-trusted identity
  if (options.role !== undefined || options.shopId !== undefined || options.customerId !== undefined || options.claims !== undefined) {
    throw new Error("Security Violation: Client cannot supply or override role, shopId, customerId, or claims.");
  }

  const identity = resolveIdentityForPhone(phone);
  const auth = options.authInstance || getAuth();
  const uid = identity.uid;
  const customClaims = identity.claims;

  // 1. Ensure user exists in Firebase Auth
  try {
    await auth.getUser(uid);
  } catch (err) {
    if (err && err.code === "auth/user-not-found") {
      await auth.createUser({
        uid,
        phoneNumber: `+91${identity.phone}`,
        displayName: identity.role === "admin"
          ? "YummBU Admin"
          : identity.role === "shopkeeper"
          ? `Shopkeeper (${identity.shopId})`
          : "YummBU Customer",
      });
    } else {
      throw err;
    }
  }

  // 2. Set custom user claims
  await auth.setCustomUserClaims(uid, customClaims);

  // 3. Create Firebase custom token embedding claims
  const customToken = await auth.createCustomToken(uid, customClaims);

  // 4. Return safe payload
  return {
    customToken,
    uid,
    role: identity.role,
    ...(identity.customerId ? { customerId: identity.customerId } : {}),
    ...(identity.shopId ? { shopId: identity.shopId } : {}),
  };
}

module.exports = {
  CANONICAL_ROLES,
  CANONICAL_ACCOUNT_STATUSES,
  SERVER_ADMIN_PHONES,
  SERVER_SHOPKEEPER_PHONE_MAP,
  SHOP_ALIASES,
  normalizeCanonicalPhone,
  canonicalizeShopId,
  buildCanonicalClaims,
  resolveIdentityForPhone,
  createCustomTokenForPhone,
};
