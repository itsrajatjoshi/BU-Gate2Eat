// BU Gate2Eat — Admin Panel
// Admin Shop Detail Screen (Direct reuse of ShopkeeperHomeScreen with isAdmin = true)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shopkeeper_panel/shopkeeper_home_screen.dart';
import 'widgets/admin_unauthorized_screen.dart';

class AdminShopDetailScreen extends ConsumerWidget {
  const AdminShopDetailScreen({
    required this.shopId,
    super.key,
  });

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isAdminAuthorized(ref)) {
      return const AdminUnauthorizedScreen();
    }
    return ShopkeeperHomeScreen(
      shopId: shopId,
      isAdmin: true,
    );
  }
}
