/**
 * YummBU — OTP Data Models & Constants (Checkpoint 1.2)
 * 
 * Defines schemas, statuses, and configuration defaults for the
 * provider-independent WhatsApp OTP challenge lifecycle.
 */

/**
 * Lifecycle statuses for an OTP Challenge record.
 */
const OtpStatus = Object.freeze({
  PENDING: "PENDING",
  VERIFIED_CONSUMED: "VERIFIED_CONSUMED",
  EXPIRED: "EXPIRED",
  LOCKED_MAX_ATTEMPTS: "LOCKED_MAX_ATTEMPTS",
  DISPATCH_FAILED: "DISPATCH_FAILED",
});

/**
 * Canonical default configuration parameters for OTP lifecycle.
 * All parameters are configurable security parameters, NOT hardcoded architecture.
 */
const DEFAULT_OTP_CONFIG = Object.freeze({
  otpLength: 6,
  expiryDurationMs: 5 * 60 * 1000, // 5 minutes
  maxAttempts: 3,
  resendCooldownMs: 60 * 1000, // 60 seconds
  cleanupRetentionMs: 24 * 60 * 60 * 1000, // 24 hours
});

/**
 * Standardized error codes for OTP authentication failures.
 * Never leak secrets, internal database details, or provider errors to clients.
 */
const OtpErrorCode = Object.freeze({
  INVALID_PHONE: "INVALID_PHONE",
  COOLDOWN_ACTIVE: "COOLDOWN_ACTIVE",
  CHALLENGE_NOT_FOUND: "CHALLENGE_NOT_FOUND",
  CHALLENGE_EXPIRED: "CHALLENGE_EXPIRED",
  CHALLENGE_ALREADY_CONSUMED: "CHALLENGE_ALREADY_CONSUMED",
  MAX_ATTEMPTS_EXCEEDED: "MAX_ATTEMPTS_EXCEEDED",
  INVALID_OTP: "INVALID_OTP",
  PROVIDER_UNAVAILABLE: "PROVIDER_UNAVAILABLE",
  SECURITY_VIOLATION: "SECURITY_VIOLATION",
  INTERNAL_ERROR: "INTERNAL_ERROR",
});

module.exports = {
  OtpStatus,
  DEFAULT_OTP_CONFIG,
  OtpErrorCode,
};
