// BU Gate2Eat — Services
// WhatsApp service for generating and launching order messages

import 'package:url_launcher/url_launcher.dart';
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
    buffer.write('~ Sent via BU Gate2Eat');

    return buffer.toString();
  }

  /// Launches WhatsApp with a pre-filled message to the shop's number.
  /// Returns true if WhatsApp was launched successfully.
  static Future<bool> launchWhatsApp({
    required String whatsappNumber,
    required String message,
  }) async {
    // Remove any spaces or special characters from phone number
    final cleanNumber = whatsappNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNumber.isEmpty) return false;

    // Build WhatsApp deep link with Indian country code
    final whatsappUrl = Uri.parse(
      'https://wa.me/91$cleanNumber?text=${Uri.encodeComponent(message)}',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Launches the phone dialer with the shop's phone number.
  static Future<bool> launchPhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNumber.isEmpty) return false;
    final phoneUrl = Uri.parse('tel:+91$cleanNumber');

    try {
      if (await canLaunchUrl(phoneUrl)) {
        await launchUrl(phoneUrl);
        return true;
      }
    } catch (_) {}

    return false;
  }
}
