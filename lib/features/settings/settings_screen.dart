// BU Gate2Eat — Settings Screen
// Application settings: theme appearance, about, legal information.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
        children: [
          // ─── Theme Section ─────────────────────────
          Text(
            'Appearance',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Theme mode selection
          _ThemeOption(
            title: 'System Default',
            subtitle: 'Follows your device settings',
            icon: Icons.brightness_auto_rounded,
            isSelected: themeMode == ThemeMode.system,
            onTap: () =>
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system),
          ),
          _ThemeOption(
            title: 'Light Mode',
            subtitle: 'Always use light theme',
            icon: Icons.light_mode_rounded,
            isSelected: themeMode == ThemeMode.light,
            onTap: () =>
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light),
          ),
          _ThemeOption(
            title: 'Dark Mode',
            subtitle: 'Always use dark theme',
            icon: Icons.dark_mode_rounded,
            isSelected: themeMode == ThemeMode.dark,
            onTap: () =>
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark),
          ),

          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),

          // ─── About Section ─────────────────────────
          Text(
            'About',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
          ),
          const SizedBox(height: AppSpacing.md),

          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Open privacy policy URL
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Open terms of service URL
            },
          ),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('App Version'),
            subtitle: Text(AppConfig.appVersion),
          ),

          // Safe area bottom spacing
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

/// A single theme option tile.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: AppColors.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}
