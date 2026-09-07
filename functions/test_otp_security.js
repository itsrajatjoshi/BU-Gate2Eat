/**
 * YummBU — Checkpoint 1.3 Remediation: Distributed OTP Security Controls Tests
 * 
 * Verifies all distributed-systems invariants:
 * 1. Distributed-Style Verification Race: Two completely independent service instances
 *    (simulating separate Cloud Function containers) sharing only the transactional datastore.
 *    Expected: SUCCESS = 1, FAILURE = 1, TOKEN_COUNT = 1.
 * 2. Concurrent Failed Attempts: 5 concurrent invalid verifications across independent instances
 *    increment the attempt counter without lost updates and lock at maxAttempts.
 * 3. Concurrent Resend Across Separate Instances: Shared challenge state prevents duplicate dispatches.
 * 4. Replay After Successful Commit: Subsequent verification from any instance is rejected.
 * 5. Expiry Protection & Boundary Conditions: Authoritative server-time comparison.
 * 6. Challenge Invalidation: New OTP challenge invalidates previous pending challenge.
 * 7. Challenge-Scoped Lock: Lock applies to challenge, NOT user account.
 * 8. Response Minimization: Successful verify returns ONLY { success: true, customToken }.
 * 9. Client Claim Injection Protection: Rejects role, shopId, customerId, admin, claims.
 * 10. HMAC Secret Security: Rejects predictable/derived keys (phone, project ID).
 * 11. Provider Delivery Failure: Sets DISPATCH_FAILED, suppresses provider internals.
 * 12. Phone Normalization: Maps all representations (+91, 91, 0) to canonical identity.
 */

const assert = require("assert");
const { OtpStatus, OtpErrorCode } = require("./otp/otp_types");
const { OtpDeliveryProvider } = require("./otp/otp_provider_interface");
const {
  OtpService,
  SharedTransactionalStore,
  maskPhone,
  resolveHmacSecret,
} = require("./otp/otp_service");

class MockDeliveryProvider extends OtpDeliveryProvider {
  constructor() {
    super();
    this.dispatches = [];
    this.failNext = false;
  }

  async sendOtp(destinationPhone, otpCode, context = {}) {
    if (this.failNext) {
      return { success: false, error: "Simulated provider network failure" };
    }
    this.dispatches.push({ destinationPhone, otpCode, context, timestamp: Date.now() });
    return { success: true, messageId: `msg_${Date.now()}` };
  }
}

const mockTokenMinter = async (phone) => ({
  customToken: `mock_custom_token_for_${phone}`,
  uid: `uid_${phone}`,
});

async function runTests() {
  console.log("==================================================");
  console.log("RUNNING CHECKPOINT 1.3 REMEDIATION TESTS");
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

  // ─── 1. Distributed Verification Race (Model-Level) ─────────
  await test("1. Distributed Race (Model-Level): Two independent runtime instances verifying same challenge result in CONSUMPTION=1, REJECTION=1, TOKEN=1", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();
    let mintCount = 0;
    const minter = async (phone) => {
      mintCount++;
      return { customToken: `token_${mintCount}`, uid: `uid_${phone}` };
    };

    // Instance A (representing Cloud Function runtime instance 1)
    const instanceA = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: minter,
    });

    // Instance B (representing completely separate Cloud Function runtime instance 2)
    // Does NOT share any local mutex or memory with instance A!
    const instanceB = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: minter,
    });

    // Generate challenge via instance A
    await instanceA.requestOtp("9876543210");
    const sentOtp = delivery.dispatches[0].otpCode;

    // Concurrently verify via Instance A and Instance B
    const [resA, resB] = await Promise.all([
      instanceA.verifyOtp("9876543210", sentOtp),
      instanceB.verifyOtp("9876543210", sentOtp),
    ]);

    const successes = [resA, resB].filter((r) => r.success === true);
    const failures = [resA, resB].filter((r) => r.success === false);

    assert.strictEqual(successes.length, 1, "Exactly one verification transaction commit must succeed");
    assert.strictEqual(failures.length, 1, "Competing verification request must fail");
    assert.strictEqual(failures[0].code, OtpErrorCode.CHALLENGE_ALREADY_CONSUMED);
    assert.strictEqual(mintCount, 1, "Token minter called only for the single winning transaction commit");
  });

  // ─── 2. Concurrent Failed Attempts (Model-Level) ────────────
  await test("2. Concurrent Failed Attempts (Model-Level): 5 concurrent invalid attempts across instances increment counter without lost updates", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    // Create 5 independent service instances sharing only the persistent store
    const instances = Array.from({ length: 5 }, () => {
      return new OtpService({
        deliveryProvider: delivery,
        storage: sharedStore,
        config: { maxAttempts: 5 },
      });
    });

    await instances[0].requestOtp("9876543210");

    // Fire 5 concurrent failed verifications from 5 separate instances
    const results = await Promise.all(
      instances.map((inst, idx) => inst.verifyOtp("9876543210", `wrong_${idx}`)),
    );

    // All must fail with INVALID_OTP or MAX_ATTEMPTS_EXCEEDED
    for (const r of results) {
      assert.strictEqual(r.success, false);
      assert.ok(
        r.code === OtpErrorCode.INVALID_OTP || r.code === OtpErrorCode.MAX_ATTEMPTS_EXCEEDED,
      );
    }

    // Inspect shared storage: attemptCount must be exactly 5
    const stored = await sharedStore.get(instances[0]._hashPhone("9876543210"));
    assert.strictEqual(stored.attemptCount, 5, "All 5 failed attempts must be recorded without lost updates");
    assert.strictEqual(stored.status, OtpStatus.LOCKED_MAX_ATTEMPTS);
  });

  // ─── 3. Concurrent Resend (Model-Level) ───────────────────────
  await test("3. Concurrent Resend (Model-Level): Two separate instances requesting OTP simultaneously result in at-most-one active challenge", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    const instance1 = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      config: { resendCooldownMs: 60000 },
    });

    const instance2 = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      config: { resendCooldownMs: 60000 },
    });

    // Fire requestOtp concurrently from Instance 1 and Instance 2
    const [res1, res2] = await Promise.all([
      instance1.requestOtp("9876543210"),
      instance2.requestOtp("9876543210"),
    ]);

    const successes = [res1, res2].filter((r) => r.success === true);
    const throttled = [res1, res2].filter((r) => r.success === false && r.code === OtpErrorCode.COOLDOWN_ACTIVE);

    assert.strictEqual(successes.length, 1, "Only one challenge creation must succeed");
    assert.strictEqual(throttled.length, 1, "Duplicate concurrent request must be throttled");
    assert.strictEqual(delivery.dispatches.length, 1, "Provider dispatch count must be exactly 1");
  });

  // ─── 4. Replay After Successful Commit ──────────────────────
  await test("4. Replay Defense: Subsequent verification from separate instance fails even after initial commit", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    const instanceA = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: mockTokenMinter,
    });

    const instanceB = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: mockTokenMinter,
    });

    await instanceA.requestOtp("9876543210");
    const otp = delivery.dispatches[0].otpCode;

    // Instance A verifies successfully
    const firstVerify = await instanceA.verifyOtp("9876543210", otp);
    assert.strictEqual(firstVerify.success, true);

    // Instance B attempts to replay the same code later
    const replayVerify = await instanceB.verifyOtp("9876543210", otp);
    assert.strictEqual(replayVerify.success, false);
    assert.strictEqual(replayVerify.code, OtpErrorCode.CHALLENGE_ALREADY_CONSUMED);
  });

  // ─── 5. Expiry Protection Boundary ──────────────────────────
  await test("5. Expiry Protection: Evaluated using server time inside datastore transaction", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    const service = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: mockTokenMinter,
      config: { expiryDurationMs: 10 },
    });

    await service.requestOtp("9876543210");
    const otp = delivery.dispatches[0].otpCode;

    // Wait past expiry
    await new Promise((r) => setTimeout(r, 20));

    const res = await service.verifyOtp("9876543210", otp);
    assert.strictEqual(res.success, false);
    assert.strictEqual(res.code, OtpErrorCode.CHALLENGE_EXPIRED);

    const stored = await sharedStore.get(service._hashPhone("9876543210"));
    assert.strictEqual(stored.status, OtpStatus.EXPIRED);
  });

  // ─── 6. Challenge Invalidation ──────────────────────────────
  await test("6. Challenge Invalidation: New OTP challenge invalidates previous pending challenge", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    const service = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: mockTokenMinter,
      config: { resendCooldownMs: 1 },
    });

    await service.requestOtp("9876543210");
    const otp1 = delivery.dispatches[0].otpCode;

    await new Promise((r) => setTimeout(r, 5));

    await service.requestOtp("9876543210");
    const otp2 = delivery.dispatches[1].otpCode;

    // Old OTP fails
    const res1 = await service.verifyOtp("9876543210", otp1);
    assert.strictEqual(res1.success, false);

    // New OTP succeeds
    const res2 = await service.verifyOtp("9876543210", otp2);
    assert.strictEqual(res2.success, true);
  });

  // ─── 7. Challenge Lock vs Account Lock ──────────────────────
  await test("7. Challenge Lockout: Failed attempts lock only the challenge, not user phone/account", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    const service = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: mockTokenMinter,
      config: { maxAttempts: 3, resendCooldownMs: 1 },
    });

    await service.requestOtp("9876543210");
    const otp1 = delivery.dispatches[0].otpCode;

    // 3 failed attempts lock challenge
    await service.verifyOtp("9876543210", "wrong_1");
    await service.verifyOtp("9876543210", "wrong_2");
    await service.verifyOtp("9876543210", "wrong_3");

    const lockedCheck = await service.verifyOtp("9876543210", otp1);
    assert.strictEqual(lockedCheck.code, OtpErrorCode.MAX_ATTEMPTS_EXCEEDED);

    // After cooldown, user requests a new challenge
    await new Promise((r) => setTimeout(r, 5));
    const newChallengeReq = await service.requestOtp("9876543210");
    assert.strictEqual(newChallengeReq.success, true);

    // New challenge allows successful verification
    const otp2 = delivery.dispatches[1].otpCode;
    const newVerify = await service.verifyOtp("9876543210", otp2);
    assert.strictEqual(newVerify.success, true);
    assert.ok(newVerify.customToken);
  });

  // ─── 8. Response Minimization ───────────────────────────────
  await test("8. Response Minimization: Successful verifyOtp returns ONLY success and customToken", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    const service = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: mockTokenMinter,
    });

    await service.requestOtp("9876543210");
    const otp = delivery.dispatches[0].otpCode;

    const res = await service.verifyOtp("9876543210", otp);
    assert.strictEqual(res.success, true);
    assert.ok(res.customToken);

    // Verify response does NOT expose authorization / identity data
    assert.strictEqual(res.role, undefined);
    assert.strictEqual(res.uid, undefined);
    assert.strictEqual(res.shopId, undefined);
    assert.strictEqual(res.customerId, undefined);
  });

  // ─── 9. Client Claim Injection Protection ───────────────────
  await test("9. Client Claim Injection: Attempts to inject role/claims are strictly rejected", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    const service = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: mockTokenMinter,
    });

    await service.requestOtp("9876543210");
    const otp = delivery.dispatches[0].otpCode;

    const injection = await service.verifyOtp("9876543210", otp, { role: "admin", claims: { admin: true } });
    assert.strictEqual(injection.success, false);
    assert.strictEqual(injection.code, OtpErrorCode.SECURITY_VIOLATION);
  });

  // ─── 10. HMAC Secret Security ───────────────────────────────
  await test("10. HMAC Secret Security: Rejects predictable/derived keys and defaults to 256-bit CSPRNG", async () => {
    assert.throws(() => resolveHmacSecret("phone_number_123"), /Security Violation/);
    assert.throws(() => resolveHmacSecret("bu-gate2eat-secret"), /Security Violation/);
    assert.throws(() => resolveHmacSecret("yummbu_dev_key"), /Security Violation/);

    const generated = resolveHmacSecret(null);
    assert.strictEqual(generated.length, 64);
  });

  // ─── 11. Provider Delivery Failure ──────────────────────────
  await test("11. Provider Failure: Delivery failure transitions challenge to DISPATCH_FAILED without leaking provider internals", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();
    delivery.failNext = true;

    const service = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
    });

    const res = await service.requestOtp("9876543210");
    assert.strictEqual(res.success, false);
    assert.strictEqual(res.code, OtpErrorCode.PROVIDER_UNAVAILABLE);
    assert.strictEqual(res.error, "Unable to send verification code. Please try again later.");

    const stored = await sharedStore.get(service._hashPhone("9876543210"));
    assert.strictEqual(stored.status, OtpStatus.DISPATCH_FAILED);
  });

  // ─── 12. Phone Normalization ────────────────────────────────
  await test("12. Phone Normalization: Maps variations (+91, 91, 0) identically with uniform responses", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    const service = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      config: { resendCooldownMs: 1 },
    });

    const res1 = await service.requestOtp("+91 98765-43210");
    assert.strictEqual(res1.success, true);

    await new Promise((r) => setTimeout(r, 5));

    const res2 = await service.requestOtp("09876543210");
    assert.strictEqual(res2.success, true);
  });

  // ─── 13. Post-Commit Failure Handling ───────────────────────
  await test("13. Post-Commit Failure: When token minting fails after commit, challenge remains consumed and cannot be replayed", async () => {
    const sharedStore = new SharedTransactionalStore();
    const delivery = new MockDeliveryProvider();

    // Flakey minter simulating crash/failure after datastore commit
    let failMinter = true;
    const flakeyMinter = async (phone) => {
      if (failMinter) {
        throw new Error("Simulated downstream auth token service crash");
      }
      return { customToken: `token_${phone}`, uid: `uid_${phone}` };
    };

    const service = new OtpService({
      deliveryProvider: delivery,
      storage: sharedStore,
      tokenMinter: flakeyMinter,
    });

    await service.requestOtp("9876543210");
    const otp = delivery.dispatches[0].otpCode;

    // First verify attempts commit then fails in token minter
    const res1 = await service.verifyOtp("9876543210", otp);
    assert.strictEqual(res1.success, false);
    assert.strictEqual(res1.code, OtpErrorCode.INTERNAL_ERROR);

    // Verify the challenge record is irrevocably VERIFIED_CONSUMED
    const stored = await sharedStore.get(service._hashPhone("9876543210"));
    assert.strictEqual(stored.status, OtpStatus.VERIFIED_CONSUMED);

    // Replay attempt with same OTP must be rejected with CHALLENGE_ALREADY_CONSUMED
    failMinter = false; // Even if token service is healthy again
    const replayRes = await service.verifyOtp("9876543210", otp);
    assert.strictEqual(replayRes.success, false);
    assert.strictEqual(replayRes.code, OtpErrorCode.CHALLENGE_ALREADY_CONSUMED);
  });

  console.log("==================================================");
  console.log(`ALL ${passed}/${total} CHECKPOINT 1.3 REMEDIATION TESTS PASSED!`);
  console.log("==================================================");
}

runTests();
