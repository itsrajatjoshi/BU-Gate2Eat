// BU Gate2Eat — Admin Panel
// Admin Shop Detail Screen (Direct reuse of ShopkeeperHomeScreen with isAdmin = true)

import 'package:flutter/material.dart';
import '../shopkeeper_panel/shopkeeper_home_screen.dart';

class AdminShopDetailScreen extends StatelessWidget {
  const AdminShopDetailScreen({
    required this.shopId,
    super.key,
  });

  final String shopId;

  @override
  Widget build(BuildContext context) {
    return ShopkeeperHomeScreen(
      shopId: shopId,
      isAdmin: true,
    );
  }
}
