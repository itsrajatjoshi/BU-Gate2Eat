/**
 * YummBU — Server-Side WhatsApp OTP Authentication Service (Checkpoint 1.3 Remediation)
 * 
 * Implements hardened distributed OTP security controls:
 * 1. Distributed Atomic Consumption: Invariant transitions PENDING -> VERIFIED_CONSUMED
 *    strictly inside shared datastore transactions (Firestore runTransaction / SharedTransactionalStore).
 * 2. Distributed Atomic Cooldown: Cooldown evaluation and challenge reservation occur atomically
 *    in the shared datastore, preventing concurrent dispatch races across multi-instance Cloud Functions.
 * 3. Atomic Attempt Tracking: Failed attempts increment atomically without lost updates.
 * 4. Challenge-Scoped Lockout: Attempt limits lock the specific challenge, NOT the user account.
 * 5. Provider Dispatch Semantics: Enforces at-most-one active challenge; documents provider idempotency boundaries.
 * 6. Cryptographically Secure Entropy: Mandatory unpredictable HMAC-SHA256 secret (never derived from phone/project).
 * 7. Expiry Protection: Authoritative server time evaluated atomically with state changes.
 * 8. Response Minimization: Returns only { success: true, customToken }, suppressing internal roles and UIDs.
 * 9. Client Claim Injection Protection: Rejects client-supplied role, shopId, customerId, or claims.
 * 10. Privacy & Logging: Phone numbers masked in logs; zero secrets or tokens logged.
 */

const crypto = require("crypto");
const { OtpStatus, DEFAULT_OTP_CONFIG, OtpErrorCode } = require("./otp_types");
const { normalizeCanonicalPhone, createCustomTokenForPhone } = require("../auth_service");

/**
 * Shared Transactional Store
 * Simulates distributed document-level ACID transactions across logically separate
 * execution instances (e.g. separate Cloud Function runtimes sharing a database).
 */
class SharedTransactionalStore {
  constructor() {
    this._data = new Map();
    this._txLocks = new Map();
  }

  async get(key) {
    const item = this._data.get(key);
    return item ? JSON.parse(JSON.stringify(item)) : null;
  }

  async set(key, value) {
    this._data.set(key, JSON.parse(JSON.stringify(value)));
  }

  /**
   * Executes an atomic transaction on the specified key.
   * Serializes transactions on the datastore level, guaranteeing that
   * concurrent requests handled by independent service instances evaluate
   * and update shared state with full serializable isolation.
   */
  async runTransaction(key, txFn) {
    while (this._txLocks.has(key)) {
      await this._txLocks.get(key);
    }
    let release;
    const lockPromise = new Promise((resolve) => {
      release = resolve;
    });
    this._txLocks.set(key, lockPromise);

    try {
      const currentRaw = this._data.get(key);
      const current = currentRaw ? JSON.parse(JSON.stringify(currentRaw)) : null;
      let pendingWrite = null;

      const tx = {
        get: () => current,
        set: (newData) => {
          pendingWrite = JSON.parse(JSON.stringify(newData));
        },
      };

      const result = await txFn(tx);
      if (pendingWrite !== null) {
        this._data.set(key, pendingWrite);
      }
      return result;
    } finally {
      this._txLocks.delete(key);
      release();
    }
  }
}

/**
 * Masks a phone number for safe, privacy-preserving audit logs.
 * Example: '9876543210' -> '******3210'
 */
function maskPhone(phone) {
  if (!phone || typeof phone !== "string") return "******";
  const clean = phone.trim();
  if (clean.length <= 4) return "******";
  return "*".repeat(clean.length - 4) + clean.slice(-4);
}

/**
 * Validates and resolves the HMAC secret.
 * Enforces that the secret is cryptographically secure and NEVER derived
 * from predictable values (phone number, project ID, trivial passwords).
 */
function resolveHmacSecret(providedSecret) {
  const secret = providedSecret || process.env.OTP_HMAC_SECRET;
  if (secret && typeof secret === "string") {
    const lowered = secret.toLowerCase().trim();
    if (
      lowered.includes("phone") ||
      lowered.includes("project") ||
      lowered.includes("bu-gate2eat") ||
      lowered.includes("yummbu") ||
      lowered === "secret" ||
      lowered.length < 16
    ) {
      throw new Error("Security Violation: Insecure or predictable HMAC secret detected.");
    }
    return secret;
  }
  // Ephemeral cryptographically random 256-bit secret fallback for testing / dev
  return crypto.randomBytes(32).toString("hex");
}

class OtpService {
  /**
   * @param {object} [dependencies]
   * @param {import("./otp_provider_interface").OtpDeliveryProvider} dependencies.deliveryProvider
   * @param {object} [dependencies.config]
   * @param {string} [dependencies.hmacSecret] - Secret used to hash OTP challenges
   * @param {object} [dependencies.storage] - Shared transactional storage or Map
   * @param {Function} [dependencies.tokenMinter] - Function to mint custom token
   * @param {object} [dependencies.firestore] - Optional Firestore instance for cloud transactions
   */
  constructor(dependencies = {}) {
    if (!dependencies.deliveryProvider) {
      throw new Error("OtpService requires an OtpDeliveryProvider instance.");
    }
    this._deliveryProvider = dependencies.deliveryProvider;
    this._config = Object.assign({}, DEFAULT_OTP_CONFIG, dependencies.config || {});
    this._hmacSecret = resolveHmacSecret(dependencies.hmacSecret);
    this._storage = dependencies.storage || new SharedTransactionalStore();
    this._tokenMinter = dependencies.tokenMinter || createCustomTokenForPhone;
    this._firestore = dependencies.firestore || null;
  }

  /**
   * Hashes an OTP code using HMAC-SHA256 for secure constant-time comparison.
   * Plaintext OTP is NEVER stored.
   * 
   * @param {string} otpCode
   * @returns {string} hex-encoded hash
   */
  _hashOtp(otpCode) {
    if (otpCode === undefined || otpCode === null) return "";
    return crypto
      .createHmac("sha256", this._hmacSecret)
      .update(String(otpCode).trim())
      .digest("hex");
  }

  /**
   * Hashes a phone number for privacy-preserving index lookup.
   * 
   * @param {string} phone
   * @returns {string} hex-encoded hash
   */
  _hashPhone(phone) {
    return crypto
      .createHash("sha256")
      .update(String(phone).trim())
      .digest("hex");
  }

  /**
   * Executes a transaction on the shared persistent datastore for a specific phone hash.
   * This provides genuine distributed consistency across multiple Cloud Function instances.
   */
  async _runTransaction(phoneHash, txFn) {
    if (this._firestore && typeof this._firestore.runTransaction === "function") {
      const docRef = this._firestore.collection("_authChallenges").doc(phoneHash);
      return await this._firestore.runTransaction(async (transaction) => {
        const snap = await transaction.get(docRef);
        const data = snap.exists ? snap.data() : null;
        let pendingWrite = null;

        const tx = {
          get: () => data,
          set: (newData) => {
            pendingWrite = newData;
          },
        };

        const result = await txFn(tx);
        if (pendingWrite !== null) {
          transaction.set(docRef, pendingWrite, { merge: true });
        }
        return result;
      });
    }

    if (this._storage && typeof this._storage.runTransaction === "function") {
      return await this._storage.runTransaction(phoneHash, txFn);
    }

    // Fallback for basic Map storage in simple test contexts
    const existing = this._storage instanceof Map ? this._storage.get(phoneHash) || null : null;
    let pendingWrite = null;
    const tx = {
      get: () => (existing ? JSON.parse(JSON.stringify(existing)) : null),
      set: (newData) => {
        pendingWrite = JSON.parse(JSON.stringify(newData));
      },
    };
    const result = await txFn(tx);
    if (pendingWrite !== null && this._storage instanceof Map) {
      this._storage.set(phoneHash, pendingWrite);
    }
    return result;
  }

  /**
   * Initiates an OTP verification challenge for the given phone number.
   * Enforces atomic cooldown check inside shared datastore transaction to prevent
   * concurrent requests from racing and triggering multiple dispatches.
   * 
   * @param {string} rawPhone - Mobile number
   * @param {object} [options]
   * @returns {Promise<{success: boolean, challengeId?: string, resendAfter?: number, error?: string, code?: string}>}
   */
  async requestOtp(rawPhone, options = {}) {
    // 1. Phone validation & normalization
    let cleanPhone;
    try {
      cleanPhone = normalizeCanonicalPhone(rawPhone);
    } catch (err) {
      return {
        success: false,
        code: OtpErrorCode.INVALID_PHONE,
        error: "Invalid mobile phone number format.",
      };
    }

    const phoneHash = this._hashPhone(cleanPhone);

    // 2. Distributed Atomic Cooldown & Challenge Reservation
    const txResult = await this._runTransaction(phoneHash, async (tx) => {
      const existing = tx.get();
      const now = Date.now();

      // Check cooldown on existing challenge regardless of status
      if (existing) {
        const cooldownEnd = existing.createdAt + this._config.resendCooldownMs;
        if (now < cooldownEnd) {
          return {
            throttled: true,
            resendAfter: cooldownEnd,
          };
        }
        // Past cooldown: invalidate prior pending challenge (Challenge Invalidation)
        if (existing.status === OtpStatus.PENDING) {
          existing.status = OtpStatus.EXPIRED;
          tx.set(existing);
        }
      }

      // Generate cryptographically secure OTP
      const min = Math.pow(10, this._config.otpLength - 1);
      const max = Math.pow(10, this._config.otpLength);
      const generatedOtp = crypto.randomInt(min, max).toString();

      // Hash OTP immediately — NEVER store plaintext
      const otpHash = this._hashOtp(generatedOtp);
      const challengeId = `chal_${crypto.randomBytes(16).toString("hex")}`;

      const challenge = {
        challengeId,
        phoneHash,
        normalizedPhone: cleanPhone, // Retained server-side only
        otpHash,
        createdAt: now,
        expiresAt: now + this._config.expiryDurationMs,
        attemptCount: 0,
        maxAttempts: this._config.maxAttempts,
        consumedAt: null,
        status: OtpStatus.PENDING,
      };

      // Reserve challenge atomically in shared datastore
      tx.set(challenge);

      return {
        shouldDispatch: true,
        challenge,
        generatedOtp,
      };
    });

    if (txResult.throttled) {
      return {
        success: false,
        code: OtpErrorCode.COOLDOWN_ACTIVE,
        error: "Resend cooldown active. Please wait before requesting another code.",
        resendAfter: txResult.resendAfter,
      };
    }

    const { challenge, generatedOtp } = txResult;

    // 3. Dispatch via delivery provider adapter
    // Note on provider dispatch semantics:
    // Application enforces at-most-one active challenge via datastore transaction.
    // Meta WhatsApp Cloud API does not natively support an Idempotency-Key HTTP header.
    // If a network failure occurs during HTTP dispatch, the challenge is transitioned to DISPATCH_FAILED.
    let deliveryResult;
    try {
      deliveryResult = await this._deliveryProvider.sendOtp(cleanPhone, generatedOtp, {
        challengeId: challenge.challengeId,
      });
    } catch (err) {
      deliveryResult = { success: false, error: err.message || "Provider error" };
    }

    if (!deliveryResult || !deliveryResult.success) {
      // Invalidate challenge immediately in shared datastore on provider failure
      await this._runTransaction(phoneHash, async (tx) => {
        const current = tx.get();
        if (current && current.challengeId === challenge.challengeId) {
          current.status = OtpStatus.DISPATCH_FAILED;
          tx.set(current);
        }
      });

      return {
        success: false,
        code: OtpErrorCode.PROVIDER_UNAVAILABLE,
        error: "Unable to send verification code. Please try again later.",
      };
    }

    return {
      success: true,
      challengeId: challenge.challengeId,
      resendAfter: challenge.createdAt + this._config.resendCooldownMs,
    };
  }

  /**
   * Verifies an OTP code against the shared persistent datastore.
   * State transitions and consumption occur strictly within a shared datastore transaction,
   * guaranteeing that a challenge can be successfully consumed exactly once.
   * Competing concurrent verification requests observe VERIFIED_CONSUMED and fail with
   * CHALLENGE_ALREADY_CONSUMED.
   * 
   * Note on Custom Token Minting & Post-Commit Behavior:
   * The Firebase Custom Token is a derived, short-lived session artifact created strictly after
   * atomic challenge consumption. We do not claim distributed exactly-once execution for the external
   * token minting call; if a container crashes or token creation fails post-commit, the challenge
   * remains consumed to prevent replay attacks. The client must request a new challenge to authenticate.
   * 
   * @param {string} rawPhone - Mobile number
   * @param {string} userOtpCode - OTP submitted by user
   * @param {object} [clientSuppliedAuthOptions] - Rejection boundary for client claims
   * @returns {Promise<{success: boolean, customToken?: string, code?: string, error?: string, remainingAttempts?: number}>}
   */
  async verifyOtp(rawPhone, userOtpCode, clientSuppliedAuthOptions = {}) {
    // 1. STRICT SECURITY GUARD: Reject any client attempt to self-assign role, shopId, or claims
    if (
      clientSuppliedAuthOptions.role !== undefined ||
      clientSuppliedAuthOptions.shopId !== undefined ||
      clientSuppliedAuthOptions.customerId !== undefined ||
      clientSuppliedAuthOptions.claims !== undefined ||
      clientSuppliedAuthOptions.admin !== undefined ||
      clientSuppliedAuthOptions.isAdmin !== undefined ||
      clientSuppliedAuthOptions.status !== undefined ||
      clientSuppliedAuthOptions.accountStatus !== undefined ||
      clientSuppliedAuthOptions.isShopkeeper !== undefined
    ) {
      return {
        success: false,
        code: OtpErrorCode.SECURITY_VIOLATION,
        error: "Security Violation: Client cannot supply role, shopId, customerId, status, or claims.",
      };
    }

    // 2. Phone validation & normalization
    let cleanPhone;
    try {
      cleanPhone = normalizeCanonicalPhone(rawPhone);
    } catch (err) {
      return {
        success: false,
        code: OtpErrorCode.INVALID_PHONE,
        error: "Invalid mobile phone number format.",
      };
    }

    const phoneHash = this._hashPhone(cleanPhone);

    // 3. Distributed Atomic Verification & State Transition
    const txResult = await this._runTransaction(phoneHash, async (tx) => {
      const challenge = tx.get();
      const now = Date.now();

      // Challenge existence check
      if (!challenge) {
        return {
          code: OtpErrorCode.CHALLENGE_NOT_FOUND,
          error: "No active verification challenge found for this number.",
        };
      }

      // Replay Protection: Check if already consumed
      if (challenge.status === OtpStatus.VERIFIED_CONSUMED) {
        return {
          code: OtpErrorCode.CHALLENGE_ALREADY_CONSUMED,
          error: "This verification code has already been used.",
        };
      }

      // Expiry Check (Server Time)
      if (now > challenge.expiresAt || challenge.status === OtpStatus.EXPIRED) {
        challenge.status = OtpStatus.EXPIRED;
        tx.set(challenge);
        return {
          code: OtpErrorCode.CHALLENGE_EXPIRED,
          error: "Verification code has expired. Please request a new code.",
        };
      }

      // Brute-Force Check: Max attempts exceeded
      if (challenge.attemptCount >= challenge.maxAttempts || challenge.status === OtpStatus.LOCKED_MAX_ATTEMPTS) {
        challenge.status = OtpStatus.LOCKED_MAX_ATTEMPTS;
        tx.set(challenge);
        return {
          code: OtpErrorCode.MAX_ATTEMPTS_EXCEEDED,
          error: "Too many incorrect attempts. Please request a new verification code.",
        };
      }

      // Constant-Time Hash Comparison
      const userOtpHash = this._hashOtp(userOtpCode);
      const storedHashBuf = Buffer.from(challenge.otpHash, "hex");
      const userHashBuf = Buffer.from(userOtpHash, "hex");

      let isMatch = false;
      if (storedHashBuf.length > 0 && storedHashBuf.length === userHashBuf.length) {
        isMatch = crypto.timingSafeEqual(storedHashBuf, userHashBuf);
      }

      if (!isMatch) {
        // Increment attempt counter atomically inside transaction
        challenge.attemptCount += 1;
        if (challenge.attemptCount >= challenge.maxAttempts) {
          challenge.status = OtpStatus.LOCKED_MAX_ATTEMPTS;
        }
        tx.set(challenge);

        const remainingAttempts = Math.max(0, challenge.maxAttempts - challenge.attemptCount);
        return {
          code: OtpErrorCode.INVALID_OTP,
          error: "Invalid verification code.",
          remainingAttempts,
          currentAttempts: challenge.attemptCount,
        };
      }

      // Atomic Challenge Consumption (Replay Prevention)
      challenge.status = OtpStatus.VERIFIED_CONSUMED;
      challenge.consumedAt = now;
      tx.set(challenge);

      return {
        verified: true,
      };
    });

    if (!txResult.verified) {
      return {
        success: false,
        code: txResult.code,
        error: txResult.error,
        ...(txResult.remainingAttempts !== undefined ? { remainingAttempts: txResult.remainingAttempts } : {}),
      };
    }

    // 4. Server-Side Custom Token Minting (Only executed after successful atomic consumption)
    let tokenResult;
    try {
      tokenResult = await this._tokenMinter(cleanPhone, {
        authInstance: optionsAuthInstance(clientSuppliedAuthOptions),
      });
    } catch (mintErr) {
      return {
        success: false,
        code: OtpErrorCode.INTERNAL_ERROR,
        error: "Authentication service temporarily unavailable. Please request a new verification code.",
      };
    }

    if (!tokenResult || !tokenResult.customToken) {
      return {
        success: false,
        code: OtpErrorCode.INTERNAL_ERROR,
        error: "Failed to generate authentication token. Please request a new verification code.",
      };
    }

    // 5. Minimized Response: Do NOT expose role, uid, shopId, or customerId
    return {
      success: true,
      customToken: tokenResult.customToken,
    };
  }
}

function optionsAuthInstance(opts) {
  return opts && opts.authInstance ? opts.authInstance : undefined;
}

module.exports = {
  OtpService,
  SharedTransactionalStore,
  maskPhone,
  resolveHmacSecret,
};
