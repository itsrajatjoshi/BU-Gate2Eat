/**
 * YummBU — OTP Delivery Provider Abstraction (Checkpoint 1.2)
 * 
 * Defines the provider-independent contract for OTP message dispatch.
 * Decouples the authentication backend from specific delivery mechanisms
 * (Meta WhatsApp Cloud API, Twilio, Gupshup, SMS gateways, Mock/Testing).
 */

class OtpDeliveryProvider {
  /**
   * Dispatches an OTP verification code to the destination phone number.
   * 
   * SECURITY CONTRACT:
   * 1. The provider receives ONLY:
   *    - destinationPhone: normalized 10-digit Indian phone
   *    - otpCode: the generated code for transmission
   *    - context: optional provider context (e.g. template ID, language)
   * 2. The provider MUST NEVER receive:
   *    - client-supplied role
   *    - client-supplied shopId
   *    - client-supplied customerId
   *    - client-selected Firebase UID
   * 3. Provider credentials (API tokens, phone IDs) MUST remain strictly server-side.
   * 
   * @param {string} destinationPhone - Normalized mobile number
   * @param {string} otpCode - Verification code to transmit
   * @param {object} [context] - Delivery context
   * @returns {Promise<{success: boolean, messageId?: string, error?: string}>}
   */
  async sendOtp(destinationPhone, otpCode, context = {}) {
    throw new Error("OtpDeliveryProvider.sendOtp() must be implemented by concrete provider adapter.");
  }
}

module.exports = {
  OtpDeliveryProvider,
};
