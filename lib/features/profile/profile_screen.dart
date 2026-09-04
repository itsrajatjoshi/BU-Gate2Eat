// BU Gate2Eat — Profile Screen
// User/account information screen (Name, Bennett University, Help & Support, etc.)
// Clearly separated from general app Settings.

import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    final localStorage = ref.read(localStorageServiceProvider);
    _nameController = TextEditingController(text: localStorage.userName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    final localStorage = ref.read(localStorageServiceProvider);
    await localStorage.updateName(name);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
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
            'Are you sure you want to log out? You will need to enter your details again to continue.',
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
    final localStorage = ref.watch(localStorageServiceProvider);
    final userName = localStorage.userName.isNotEmpty ? localStorage.userName : 'Student';

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 16.0;

    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          try {
            context.go(AppRoutes.home);
          } catch (_) {}
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Profile',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                try {
                  context.go(AppRoutes.home);
                } catch (_) {}
              }
            },
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.divider,
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
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
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.person_rounded,
                      size: 32,
                      color: AppColors.primary,
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
                      const SizedBox(height: 4),
                      const Row(
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Bennett University',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
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

          // ─── 3. Account Information & App Details ───────
          Text(
            'About & Legal',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),

          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.divider,
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
                    leading: const Icon(Icons.help_outline_rounded, color: AppColors.primary),
                    title: const Text('Help & Support'),
                    subtitle: const Text('Contact us or send a query'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      context.push(AppRoutes.helpAndSupport);
                    },
                  ),
                  const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
                  ListTile(
                    leading: const Icon(Icons.description_outlined, color: AppColors.primary),
                    title: const Text('Privacy Policy'),
                    subtitle: const Text('Read our privacy practices'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Open privacy policy URL
                    },
                  ),
                  const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined, color: AppColors.secondary),
                    title: const Text('Terms of Service'),
                    subtitle: const Text('Terms & conditions of use'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Open terms of service URL
                    },
                  ),
                  const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
                  const ListTile(
                    leading: Icon(Icons.info_outline_rounded, color: AppColors.info),
                    title: Text('App Version'),
                    subtitle: Text('${AppConfig.appVersion} (${AppConfig.appName})'),
                  ),
                  const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: AppColors.yummbuRed),
                    title: const Text(
                      'Logout',
                      style: TextStyle(
                        color: AppColors.yummbuRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text('Sign out from this device'),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.yummbuRed),
                    onTap: _showLogoutDialog,
                  ),

                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

