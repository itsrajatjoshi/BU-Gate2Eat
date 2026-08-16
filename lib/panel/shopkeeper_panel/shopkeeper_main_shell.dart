// BU Gate2Eat — Shopkeeper Panel
// Main Shell with exactly 3 bottom tabs: Home | Orders | Profile
// Visual styling identical to User App HomeScreen

import 'package:flutter/material.dart';
import 'shopkeeper_home_screen.dart';
import 'shopkeeper_orders_screen.dart';
import 'shopkeeper_profile_screen.dart';

class ShopkeeperMainShell extends StatefulWidget {
  const ShopkeeperMainShell({super.key});

  @override
  State<ShopkeeperMainShell> createState() => _ShopkeeperMainShellState();
}

class _ShopkeeperMainShellState extends State<ShopkeeperMainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    ShopkeeperHomeScreen(),
    ShopkeeperOrdersScreen(),
    ShopkeeperProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
