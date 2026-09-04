// BU Gate2Eat — Admin Panel
// Admin Profile Screen (Rajat Joshi / Administrator / 8078643910)
// Matching exact visual styling of User & Shopkeeper Profile screens

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';

class AdminProfileScreen extends ConsumerStatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  ConsumerState<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends ConsumerState<AdminProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _ageController;

  @override
  void initState() {
    super.initState();
    final localStorage = ref.read(localStorageServiceProvider);
    final initialName =
        localStorage.userName.isNotEmpty ? localStorage.userName : 'Rajat Joshi';
    final initialPhone = localStorage.userPhone.isNotEmpty
        ? localStorage.userPhone
        : AppAuthRoles.adminPhone;
    final initialAge =
        localStorage.userAge > 0 ? localStorage.userAge.toString() : '25';

    _nameController = TextEditingController(text: initialName);
    _phoneController = TextEditingController(text: initialPhone);
    _ageController = TextEditingController(text: initialAge);
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
    final ageText = _ageController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name cannot be empty'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final localStorage = ref.read(localStorageServiceProvider);
    await localStorage.updateName(name);

    if (ageText.isNotEmpty) {
      final parsedAge = int.tryParse(ageText);
      if (parsedAge != null && parsedAge > 0 && parsedAge < 120) {
        await localStorage.updateAge(parsedAge);
      }
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Admin Profile updated successfully'),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showLogoutDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: AppColors.error, size: 24),
              SizedBox(width: 8),
              Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out from the Admin Panel?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await clearCustomerSession(ref);

      if (mounted) {
        context.go(AppRoutes.onboarding);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final localStorage = ref.watch(localStorageServiceProvider);
    final userName = localStorage.userName.isNotEmpty
        ? localStorage.userName
        : 'Rajat Joshi';
    final rawPhone = localStorage.userPhone.isNotEmpty
        ? localStorage.userPhone
        : AppAuthRoles.adminPhone;
    final userPhone = '+91 $rawPhone';
    final initialLetter =
        userName.isNotEmpty ? userName[0].toUpperCase() : 'A';

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
                      initialLetter,
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        userPhone,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.admin_panel_settings_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'YummBU Administrator • Full Access',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
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

          // ─── 2. Personal Information Section ────────────
          Text(
            'Personal Information',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),

          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
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
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _phoneController,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Phone Number (Admin Account Identity)',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    prefixText: '+91 ',
                    isDense: true,
                    suffixIcon: Tooltip(
                      message: 'Phone number is permanently linked to your Admin role',
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textHint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    prefixIcon: Icon(Icons.cake_outlined),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ─── 3. Account Actions ─────────────────────────
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark ? AppColors.darkDivider : AppColors.divider,
                width: 0.8,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.support_agent_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text('Customer Queries'),
                    subtitle: const Text('View customer support queries'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      context.push(AppRoutes.adminCustomerQueries);
                    },
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkDivider : AppColors.divider,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.description_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text('Privacy Policy'),
                    subtitle: const Text('Read our privacy practices'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {},
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkDivider : AppColors.divider,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.gavel_outlined,
                      color: AppColors.secondary,
                    ),
                    title: const Text('Terms of Service'),
                    subtitle: const Text('Terms & conditions of use'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {},
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkDivider : AppColors.divider,
                  ),
                  const ListTile(
                    leading: Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.info,
                    ),
                    title: Text('App Version'),
                    subtitle: Text('${AppConfig.appVersion} (${AppConfig.appName})'),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkDivider : AppColors.divider,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.yummbuRed,
                    ),
                    title: const Text(
                      'Logout',
                      style: TextStyle(color: AppColors.yummbuRed),
                    ),
                    subtitle: const Text('Sign out from this device'),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.yummbuRed,
                    ),
                    onTap: _showLogoutDialog,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
