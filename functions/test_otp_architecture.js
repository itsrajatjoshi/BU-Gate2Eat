/**
 * YummBU — Checkpoint 1.2: WhatsApp OTP Backend Architecture Tests
 * 
 * Verifies all 5 required architecture and security areas:
 * 1. Provider Abstraction: OtpDeliveryProvider interface & MetaWhatsAppProvider boundary.
 * 2. OTP Storage Security: Plaintext OTP is NEVER stored in challenge records.
 * 3. Verification & Replay Protection:
 *    - Rejects non-existent challenges.
 *    - Rejects expired challenges.
 *    - Prevents replay (atomic consumption rejects second verification attempt).
 *    - Enforces attempt counter and brute-force lockout.
 *    - Strictly rejects client-supplied role, shopId, or customerId.
 * 4. Custom Token Boundary: Server-side token minting only upon successful verification.
 * 5. Error Safety: Internal errors & provider failures are sanitized.
 */

const assert = require("assert");
const { OtpStatus, OtpErrorCode, DEFAULT_OTP_CONFIG } = require("./otp/otp_types");
const { OtpDeliveryProvider } = require("./otp/otp_provider_interface");
const { MetaWhatsAppProvider } = require("./otp/meta_whatsapp_provider");
const { OtpService } = require("./otp/otp_service");

// Mock delivery provider capturing sent payload
class MockDeliveryProvider extends OtpDeliveryProvider {
  constructor() {
    super();
    this.dispatches = [];
    this.failNext = false;
  }

  async sendOtp(destinationPhone, otpCode, context = {}) {
    if (this.failNext) {
      return { success: false, error: "Simulated network timeout" };
    }
    this.dispatches.push({ destinationPhone, otpCode, context, timestamp: Date.now() });
    return { success: true, messageId: `mock_msg_${Date.now()}` };
  }
}

// Mock token minter that tracks calls
async function mockTokenMinter(phone, options = {}) {
  return {
    customToken: `mock_token_for_${phone}`,
    uid: `phone_${phone}`,
    role: phone === "8078643910" ? "admin" : (phone === "8000383993" ? "shopkeeper" : "customer"),
    ...(phone === "8000383993" ? { shopId: "rajat_shop" } : {}),
    ...(phone !== "8078643910" && phone !== "8000383993" ? { customerId: `cust_${phone}` } : {}),
  };
}

async function runTests() {
  console.log("==================================================");
  console.log("RUNNING CHECKPOINT 1.2 OTP ARCHITECTURE TESTS");
  console.log("==================================================");

  let passed = 0;
  let total = 0;

  async function test(name, fn) {
    total++;
    try {
      await fn();
      console.log(`✅ [PASS] ${total}. ${name}`);
      passed++;
    } catch (err) {
      console.error(`❌ [FAIL] ${total}. ${name}`);
      console.error(err);
      process.exit(1);
    }
  }

  // ─── 1. Provider Abstraction Tests ─────────────────────────
  await test("1. OtpDeliveryProvider abstract class enforces interface contract", async () => {
    const baseProvider = new OtpDeliveryProvider();
    await assert.rejects(
      async () => baseProvider.sendOtp("9876543210", "123456"),
      /must be implemented/,
    );
  });

  await test("2. MetaWhatsAppProvider extends OtpDeliveryProvider and operates behind provider boundary", async () => {
    const metaProvider = new MetaWhatsAppProvider({ isDryRun: true });
    assert.ok(metaProvider instanceof OtpDeliveryProvider);
    const result = await metaProvider.sendOtp("9876543210", "123456");
    assert.strictEqual(result.success, true);
    assert.ok(result.messageId.startsWith("dry_run_msg_"));
  });

  // ─── 2. OTP Storage Security Tests ─────────────────────────
  await test("3. Plaintext OTP is NEVER stored in persistent challenge record", async () => {
    const delivery = new MockDeliveryProvider();
    const storage = new Map();
    const service = new OtpService({
      deliveryProvider: delivery,
      storage,
      tokenMinter: mockTokenMinter,
    });

    const res = await service.requestOtp("9876543210");
    assert.strictEqual(res.success, true);
    assert.strictEqual(delivery.dispatches.length, 1);
    const sentOtp = delivery.dispatches[0].otpCode;

    // Inspect storage map
    assert.strictEqual(storage.size, 1);
    const [storedChallenge] = storage.values();

    // Invariants:
    assert.strictEqual(storedChallenge.otp, undefined, "Plaintext 'otp' field must not exist");
    assert.strictEqual(storedChallenge.plaintextOtp, undefined, "Plaintext field must not exist");
    assert.ok(storedChallenge.otpHash, "otpHash must exist");
    assert.notStrictEqual(storedChallenge.otpHash, sentOtp, "otpHash must not equal plaintext OTP");
    assert.strictEqual(storedChallenge.otpHash.length, 64, "otpHash must be SHA-256 / HMAC hex length");
  });

  // ─── 3. Verification & Replay Protection Tests ─────────────
  await test("4. Verification requires active challenge; rejects non-existent challenge", async () => {
    const delivery = new MockDeliveryProvider();
    const service = new OtpService({
      deliveryProvider: delivery,
      tokenMinter: mockTokenMinter,
    });

    const res = await service.verifyOtp("9876543210", "123456");
    assert.strictEqual(res.success, false);
    assert.strictEqual(res.code, OtpErrorCode.CHALLENGE_NOT_FOUND);
  });

  await test("5. Expired challenge is rejected and updated to EXPIRED status", async () => {
    const delivery = new MockDeliveryProvider();
    const storage = new Map();
    const service = new OtpService({
      deliveryProvider: delivery,
      storage,
      config: { expiryDurationMs: 1 }, // 1ms expiry
      tokenMinter: mockTokenMinter,
    });

    await service.requestOtp("9876543210");
    const sentOtp = delivery.dispatches[0].otpCode;

    // Wait 10ms for expiry
    await new Promise((r) => setTimeout(r, 10));

    const res = await service.verifyOtp("9876543210", sentOtp);
    assert.strictEqual(res.success, false);
    assert.strictEqual(res.code, OtpErrorCode.CHALLENGE_EXPIRED);
  });

  await test("6. Replay Protection: Successfully consumed challenge CANNOT be verified again", async () => {
    const delivery = new MockDeliveryProvider();
    const storage = new Map();
    const service = new OtpService({
      deliveryProvider: delivery,
      storage,
      tokenMinter: mockTokenMinter,
    });

    await service.requestOtp("9876543210");
    const sentOtp = delivery.dispatches[0].otpCode;

    // First verification -> Success
    const firstRes = await service.verifyOtp("9876543210", sentOtp);
    assert.strictEqual(firstRes.success, true);
    assert.ok(firstRes.customToken);

    // Second verification with identical OTP -> REPLAY PREVENTED
    const replayRes = await service.verifyOtp("9876543210", sentOtp);
    assert.strictEqual(replayRes.success, false);
    assert.strictEqual(replayRes.code, OtpErrorCode.CHALLENGE_ALREADY_CONSUMED);
  });

  await test("7. Attempt counter tracks failed attempts and locks out brute force", async () => {
    const delivery = new MockDeliveryProvider();
    const storage = new Map();
    const service = new OtpService({
      deliveryProvider: delivery,
      storage,
      config: { maxAttempts: 3 },
      tokenMinter: mockTokenMinter,
    });

    await service.requestOtp("9876543210");

    // Attempt 1: wrong code
    const att1 = await service.verifyOtp("9876543210", "000000");
    assert.strictEqual(att1.success, false);
    assert.strictEqual(att1.code, OtpErrorCode.INVALID_OTP);
    assert.strictEqual(att1.remainingAttempts, 2);

    // Attempt 2: wrong code
    const att2 = await service.verifyOtp("9876543210", "000001");
    assert.strictEqual(att2.remainingAttempts, 1);

    // Attempt 3: wrong code -> Locks
    const att3 = await service.verifyOtp("9876543210", "000002");
    assert.strictEqual(att3.remainingAttempts, 0);

    // Attempt 4: Even with CORRECT code, locked challenge is rejected
    const sentOtp = delivery.dispatches[0].otpCode;
    const att4 = await service.verifyOtp("9876543210", sentOtp);
    assert.strictEqual(att4.success, false);
    assert.strictEqual(att4.code, OtpErrorCode.MAX_ATTEMPTS_EXCEEDED);
  });

  await test("8. Client CANNOT choose or override role, shopId, or customerId (Security Violation)", async () => {
    const delivery = new MockDeliveryProvider();
    const service = new OtpService({
      deliveryProvider: delivery,
      tokenMinter: mockTokenMinter,
    });

    await service.requestOtp("9876543210");
    const sentOtp = delivery.dispatches[0].otpCode;

    // Rogue client attempts to inject role = admin
    const rogueRes = await service.verifyOtp("9876543210", sentOtp, {
      role: "admin",
    });
    assert.strictEqual(rogueRes.success, false);
    assert.strictEqual(rogueRes.code, OtpErrorCode.SECURITY_VIOLATION);
  });

  // ─── 4. Custom Token Boundary Tests ─────────────────────────
  await test("9. Custom Token minting occurs strictly on backend upon successful verification", async () => {
    let minterCalled = false;
    const customMinter = async (phone) => {
      minterCalled = true;
      return {
        customToken: "backend_minted_custom_token_xyz",
        uid: `phone_${phone}`,
        role: "customer",
      };
    };

    const delivery = new MockDeliveryProvider();
    const service = new OtpService({
      deliveryProvider: delivery,
      tokenMinter: customMinter,
    });

    await service.requestOtp("9876543210");
    const sentOtp = delivery.dispatches[0].otpCode;

    const res = await service.verifyOtp("9876543210", sentOtp);
    assert.strictEqual(res.success, true);
    assert.strictEqual(minterCalled, true, "Server-side token minter must be invoked");
    assert.strictEqual(res.customToken, "backend_minted_custom_token_xyz");
    assert.strictEqual(res.uid, undefined, "uid must not be exposed in verify response");
    assert.strictEqual(res.role, undefined, "role must not be exposed in verify response");
  });

  // ─── 5. Error Safety & Failure Handling Tests ───────────────
  await test("10. Provider delivery failure is sanitized and does not leak internal stack traces", async () => {
    const delivery = new MockDeliveryProvider();
    delivery.failNext = true;

    const service = new OtpService({
      deliveryProvider: delivery,
      tokenMinter: mockTokenMinter,
    });

    const res = await service.requestOtp("9876543210");
    assert.strictEqual(res.success, false);
    assert.strictEqual(res.code, OtpErrorCode.PROVIDER_UNAVAILABLE);
    assert.strictEqual(res.error, "Unable to send verification code. Please try again later.");
    assert.strictEqual(res.challengeId, undefined);
  });

  await test("11. Resend cooldown prevents spamming the delivery provider", async () => {
    const delivery = new MockDeliveryProvider();
    const service = new OtpService({
      deliveryProvider: delivery,
      config: { resendCooldownMs: 60000 },
      tokenMinter: mockTokenMinter,
    });

    const first = await service.requestOtp("9876543210");
    assert.strictEqual(first.success, true);

    const second = await service.requestOtp("9876543210");
    assert.strictEqual(second.success, false);
    assert.strictEqual(second.code, OtpErrorCode.COOLDOWN_ACTIVE);
    assert.ok(second.resendAfter > Date.now());
  });

  console.log("==================================================");
  console.log(`ALL ${passed}/${total} CHECKPOINT 1.2 TESTS PASSED!`);
  console.log("==================================================");
}

runTests();
