// BU Gate2Eat — Data Models
// Order model for In-App Orders

/// Represents an individual item snapshot within an order.
class OrderItem {
  const OrderItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    this.imageUrl = '',
  });

  final String menuItemId;
  final String name;
  final int price;
  final int quantity;
  final String imageUrl;

  double get totalPrice => (price * quantity).toDouble();
}

/// Represents a customer order.
class AppOrder {
  const AppOrder({
    required this.orderId,
    required this.shopId,
    required this.shopName,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    this.specialInstructions = '',
    this.deliveryNote = 'Bennett University',
    this.status = 'placed',
  });

  final String orderId;
  final String shopId;
  final String shopName;
  final String customerName;
  final String customerPhone;
  final List<OrderItem> items;
  final double totalAmount;
  final String specialInstructions;
  final String deliveryNote;
  final String status;
  final DateTime createdAt;

  int get totalItemCount =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

  String get formattedTotal => '₹${totalAmount.toStringAsFixed(0)}';

  AppOrder copyWith({
    String? status,
  }) {
    return AppOrder(
      orderId: orderId,
      shopId: shopId,
      shopName: shopName,
      customerName: customerName,
      customerPhone: customerPhone,
      items: items,
      totalAmount: totalAmount,
      specialInstructions: specialInstructions,
      deliveryNote: deliveryNote,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
