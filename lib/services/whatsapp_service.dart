// BU Gate2Eat — Services
// WhatsApp service for generating and launching order messages

import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../models/cart_item_model.dart';

/// Service for generating WhatsApp order messages and launching WhatsApp.
class WhatsAppService {
  /// Generates the order message text from cart items and user info.
  static String generateOrderMessage({
    required String shopName,
    required String userName,
    required String userPhone,
    required List<CartItem> cartItems,
    String? specialInstructions,
  }) {
    final buffer = StringBuffer();

    // Greeting
    buffer.writeln('Hello $shopName,');
    buffer.writeln();

    // User info
    buffer.writeln('Name: $userName');
    buffer.writeln('Phone: $userPhone');
    buffer.writeln();

    // Items
    buffer.writeln('Items:');
    for (final item in cartItems) {
      buffer.writeln(
        '• ${item.quantity} × ${item.menuItem.name} — ₹${item.totalPrice.toStringAsFixed(0)}',
      );
    }
    buffer.writeln();

    // Total
    final grandTotal = cartItems.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );
    buffer.writeln('Total: ₹${grandTotal.toStringAsFixed(0)}');
    buffer.writeln();

    // Special instructions (only if provided)
    if (specialInstructions != null && specialInstructions.trim().isNotEmpty) {
      buffer.writeln('Special Instructions: ${specialInstructions.trim()}');
      buffer.writeln();
    }

    // Pickup location
    buffer.writeln('I will collect the order from Bennett Gate No. 2.');
    buffer.writeln();

    // Branding
    buffer.write(AppConfig.whatsappBranding);

    return buffer.toString();
  }

  /// Normalizes a phone number to Indian international format without leading + (e.g. 919876543210).
  /// Returns an empty string if the number is invalid or missing.
  static String normalizePhoneNumber(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    // Strip leading zero if present (e.g. 09876543210)
    if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }

    // If 12 digits and starts with 91 (e.g. 919876543210)
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits;
    }

    // If 10 digits (e.g. 9876543210)
    if (digits.length == 10) {
      return '91$digits';
    }

    // If international number with at least 10 digits and already has country code
    if (digits.length >= 10 && digits.length <= 15) {
      return digits;
    }

    return '';
  }

  /// Builds a Uri for WhatsApp with prefilled message.
  /// Returns null if phone number is invalid.
  static Uri? buildWhatsAppUri({
    required String whatsappNumber,
    required String message,
  }) {
    final formattedNumber = normalizePhoneNumber(whatsappNumber);
    if (formattedNumber.isEmpty) return null;

    return Uri.parse(
      'https://wa.me/$formattedNumber?text=${Uri.encodeComponent(message)}',
    );
  }

  /// Launches WhatsApp with a pre-filled message to the shop's number.
  /// Returns true if WhatsApp was launched successfully.
  static Future<bool> launchWhatsApp({
    required String whatsappNumber,
    required String message,
  }) async {
    final uri = buildWhatsAppUri(
      whatsappNumber: whatsappNumber,
      message: message,
    );
    if (uri == null) return false;

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Launches the phone dialer with the shop's phone number.
  static Future<bool> launchPhoneCall(String phoneNumber) async {
    final formattedNumber = normalizePhoneNumber(phoneNumber);
    if (formattedNumber.isEmpty) return false;

    final phoneUrl = Uri.parse('tel:+$formattedNumber');

    try {
      if (await canLaunchUrl(phoneUrl)) {
        await launchUrl(phoneUrl);
        return true;
      }
    } catch (_) {}

    return false;
  }
}
