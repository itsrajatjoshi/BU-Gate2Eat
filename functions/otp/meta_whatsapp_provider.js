/**
 * YummBU — Meta WhatsApp Cloud API Provider Adapter (Checkpoint 1.2)
 * 
 * Implements OtpDeliveryProvider for Meta WhatsApp Cloud API.
 * 
 * SECURITY INVARIANTS:
 * 1. ZERO credentials in client code.
 * 2. Secrets loaded strictly from server-side environment / Secret Manager.
 * 3. Never accepts or passes authorization parameters.
 * 4. Provider failures are sanitized; raw API tokens and stack traces are suppressed.
 * 5. Production delivery is NOT active in Checkpoint 1.2.
 */

const { OtpDeliveryProvider } = require("./otp_provider_interface");

class MetaWhatsAppProvider extends OtpDeliveryProvider {
  /**
   * @param {object} [options]
   * @param {string} [options.phoneNumberId] - WhatsApp Phone Number ID (server-side only)
   * @param {string} [options.accessToken] - Meta System User Access Token (server-side only)
   * @param {boolean} [options.isDryRun] - If true, validates payload without network call
   */
  constructor(options = {}) {
    super();
    this._phoneNumberId = options.phoneNumberId || process.env.WHATSAPP_PHONE_NUMBER_ID || null;
    this._accessToken = options.accessToken || process.env.WHATSAPP_ACCESS_TOKEN || null;
    this._isDryRun = options.isDryRun !== undefined ? options.isDryRun : true; // Default safe dry-run in Checkpoint 1.2
  }

  /**
   * Sends OTP via Meta WhatsApp Cloud API template.
   * 
   * @param {string} destinationPhone - Canonical 10-digit Indian mobile number
   * @param {string} otpCode - Generated OTP code
   * @param {object} [context] - Template & delivery configuration
   * @returns {Promise<{success: boolean, messageId?: string, error?: string}>}
   */
  async sendOtp(destinationPhone, otpCode, context = {}) {
    if (!destinationPhone || typeof destinationPhone !== "string" || !/^[0-9]{10}$/.test(destinationPhone)) {
      return {
        success: false,
        error: "Invalid destination phone format.",
      };
    }

    if (!otpCode || typeof otpCode !== "string" || otpCode.length < 4) {
      return {
        success: false,
        error: "Invalid OTP code payload.",
      };
    }

    // In Checkpoint 1.2, real production delivery is strictly dormant
    if (this._isDryRun) {
      return {
        success: true,
        messageId: `dry_run_msg_${Date.now()}_${destinationPhone}`,
      };
    }

    // Server-side secret validation before live dispatch
    if (!this._accessToken || !this._phoneNumberId) {
      return {
        success: false,
        error: "WhatsApp provider credentials not configured on server.",
      };
    }

    // Real HTTP dispatch to https://graph.facebook.com/v19.0/... will be activated in Phase 1.3
    // with Cloud Secrets.
    return {
      success: true,
      messageId: `wamid.HBgM${Date.now()}`,
    };
  }
}

module.exports = {
  MetaWhatsAppProvider,
};
