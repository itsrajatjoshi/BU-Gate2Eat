// BU Gate2Eat — Admin Panel
// Admin Home Screen (Direct reuse of User HomeTabContent + Add Shop FAB)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../features/home/home_screen.dart';
import 'widgets/add_shop_modal.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeTabContent(
      onShopTap: (shop) => context.push('/admin/shop/${shop.id}'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddShopModal.show(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_business_rounded, color: Colors.white),
        label: const Text(
          'Add Shop',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
