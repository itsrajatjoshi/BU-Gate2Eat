// BU Gate2Eat — Profile Screen
// User/account information screen (Name, Phone, Age, Pickup Info)
// Clearly separated from general app Settings.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _ageController;

  @override
  void initState() {
    super.initState();
    final localStorage = ref.read(localStorageServiceProvider);
    _nameController = TextEditingController(text: localStorage.userName);
    _phoneController = TextEditingController(text: localStorage.userPhone);
    _ageController = TextEditingController(
      text: localStorage.userAge > 0 ? localStorage.userAge.toString() : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final ageText = _ageController.text.trim();

    if (name.isEmpty || phone.isEmpty || ageText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    if (phone.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit phone number')),
      );
      return;
    }

    final age = int.tryParse(ageText);
    if (age == null || age < 15 || age > 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid age (15-30)')),
      );
      return;
    }

    final localStorage = ref.read(localStorageServiceProvider);
    await localStorage.saveUserProfile(name: name, phone: phone, age: age);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final localStorage = ref.watch(localStorageServiceProvider);
    final userName = localStorage.userName.isNotEmpty ? localStorage.userName : 'Student';
    final userPhone = localStorage.userPhone.isNotEmpty ? '+91 ${localStorage.userPhone}' : '';

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          16,
          horizontalPadding,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // ─── 1. User Header Card ────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark ? AppColors.darkDivider : AppColors.divider,
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                      ),
                      if (userPhone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          userPhone,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Bennett University • Gate 2',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ─── 2. Edit Profile Details Form ───────────────
          Text(
            'Personal Details',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Name field
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Phone field
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone_outlined),
              prefixText: '+91 ',
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Age field
          TextField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: const InputDecoration(
              labelText: 'Age',
              prefixIcon: Icon(Icons.cake_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text(
                'Save Changes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ─── 3. Account Information & Shortcuts ─────────
          Text(
            'Account Information',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),

          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark ? AppColors.darkDivider : AppColors.divider,
                width: 0.8,
              ),
            ),
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.local_shipping_outlined, color: AppColors.primary),
                  title: Text('Pickup Location'),
                  subtitle: Text('Bennett University Gate No. 2'),
                ),
                Divider(
                  height: 1,
                  thickness: 0.6,
                  color: isDark ? AppColors.darkDivider : AppColors.divider,
                ),
                const ListTile(
                  leading: Icon(Icons.chat_bubble_outline_rounded, color: AppColors.success),
                  title: Text('Ordering Method'),
                  subtitle: Text('Direct WhatsApp with Vendor'),
                ),
                Divider(
                  height: 1,
                  thickness: 0.6,
                  color: isDark ? AppColors.darkDivider : AppColors.divider,
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined, color: AppColors.secondary),
                  title: const Text('Appearance & App Settings'),
                  subtitle: const Text('Theme, About, Legal'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.settings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
