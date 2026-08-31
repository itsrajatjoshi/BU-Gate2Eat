// BU Gate2Eat — Admin Panel
// Add Shop Modal (Real Firestore Creation & Firebase Storage Banner Upload)

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../models/shop_model.dart';
import '../../../services/image_optimization_service.dart';

class AddShopModal extends ConsumerStatefulWidget {
  const AddShopModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddShopModal(),
    );
  }

  @override
  ConsumerState<AddShopModal> createState() => _AddShopModalState();
}

class _AddShopModalState extends ConsumerState<AddShopModal> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _openTimeController =
      TextEditingController(text: '8:00 AM');
  final TextEditingController _closeTimeController =
      TextEditingController(text: '11:30 PM');
  final TextEditingController _pickupNoteController =
      TextEditingController(text: 'Pickup from Gate 3');
  final TextEditingController _contactController = TextEditingController();

  bool _isLoading = false;
  bool _isOptimizingImage = false;

  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedBannerBytes;
  int? _selectedBannerSizeBytes;
  String? _bannerError;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _openTimeController.dispose();
    _closeTimeController.dispose();
    _pickupNoteController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  TimeOfDay _parseToTimeOfDay(String timeStr, TimeOfDay fallback) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPm = clean.contains('PM');
      final isAm = clean.contains('AM');

      final numericPart = clean.replaceAll(RegExp(r'[^\d:]'), '');
      final parts = numericPart.split(':');
      if (parts.length >= 2) {
        var h = int.parse(parts[0]);
        final m = int.parse(parts[1]);

        if (isPm && h < 12) h += 12;
        if (isAm && h == 12) h = 0;

        return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _pickTimeDialog({
    required TextEditingController controller,
    required String title,
    required TimeOfDay initialTime,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: title,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null && mounted) {
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      final hour12 = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final minuteStr = picked.minute.toString().padLeft(2, '0');
      final formattedString = '$hour12:$minuteStr $period';

      setState(() {
        controller.text = formattedString;
      });
    }
  }

  Future<void> _pickBanner() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _isOptimizingImage = true;
          _bannerError = null;
        });

        final rawBytes = await picked.readAsBytes();
        final optimized = await ImageOptimizationService.optimizeImageBytes(
          originalBytes: rawBytes,
          type: ImageTargetType.shopBanner,
        );

        if (mounted) {
          setState(() {
            _selectedBannerBytes = optimized;
            _selectedBannerSizeBytes = optimized.lengthInBytes;
            _isOptimizingImage = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOptimizingImage = false;
          _bannerError = 'Failed to process image. Please try again.';
        });
      }
    }
  }

  Future<void> _onCreateShop() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Shop Name cannot be empty.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      final cleanId = name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final shopId = cleanId.isNotEmpty
          ? cleanId
          : 'shop_${DateTime.now().millisecondsSinceEpoch}';

      final formattedOpen = _openTimeController.text.trim().isEmpty
          ? '8:00 AM'
          : Shop.format12hr(_openTimeController.text.trim());
      final formattedClose = _closeTimeController.text.trim().isEmpty
          ? '11:30 PM'
          : Shop.format12hr(_closeTimeController.text.trim());

      final newShop = Shop(
        id: shopId,
        name: name,
        description: _descController.text.trim(),
        bannerUrl: '',
        contactNumber: _contactController.text.trim(),
        orderNumber: _contactController.text.trim(),
        openTime: formattedOpen,
        closeTime: formattedClose,
        isClosedOverride: false,
        isActive: true,
        sortOrder: 10,
        searchKeywords: [
          name.toLowerCase(),
          ...name.toLowerCase().split(' ').where((w) => w.length > 2),
        ],
        deliveryNote: _pickupNoteController.text.trim().isEmpty
            ? 'Pickup from Gate 3'
            : _pickupNoteController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await firestoreService.createShop(
        newShop,
        bannerBytes: _selectedBannerBytes,
      );

      ref.invalidate(shopsProvider);

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '"$name" created successfully!',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create shop: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkDivider
                      : AppColors.divider.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add_business_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add New Shop',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                          ),
                          Text(
                            'Create a new food outlet in YummBU',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scrollable Form Fields
              Expanded(
                child: ListView(
                  children: [
                    // ─── 1. Shop Banner Section ────────────────────────────
                    Row(
                      children: [
                        Text(
                          'Shop Banner Photo',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.textSecondary,
                                  ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Auto-Optimized ≤ 800 KB',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    if (_isOptimizingImage)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Optimizing banner photo for high speed...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_selectedBannerBytes != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _selectedBannerBytes!,
                                width: 72,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'New banner ready',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (_selectedBannerSizeBytes != null)
                                    Text(
                                      '${(_selectedBannerSizeBytes! / 1024).toStringAsFixed(1)} KB (High Speed)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _pickBanner,
                              icon: const Icon(
                                Icons.refresh_rounded,
                                size: 16,
                              ),
                              label: const Text('Change'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: _pickBanner,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 54),
                          side: BorderSide(
                            color: isDark
                                ? AppColors.darkDivider
                                : AppColors.divider,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        label: const Text(
                          'Upload Shop Banner Image',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],

                    if (_bannerError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _bannerError!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ─── 2. Shop Name ────────────────────────────────────
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Shop Name *',
                        hintText: 'e.g. Punjabi Dhaba',
                        prefixIcon: Icon(Icons.store_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ─── 3. Description ─────────────────────────────────
                    TextField(
                      controller: _descController,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description / Food Highlights',
                        hintText: 'e.g. North Indian Thalis, Parathas & Lassi',
                        prefixIcon: Icon(Icons.description_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ─── 4. Operating Hours Row (12hr AM/PM) ───────────
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              final current = _parseToTimeOfDay(
                                _openTimeController.text,
                                const TimeOfDay(hour: 8, minute: 0),
                              );
                              _pickTimeDialog(
                                controller: _openTimeController,
                                title: 'Select Opening Time',
                                initialTime: current,
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: IgnorePointer(
                              child: TextField(
                                controller: _openTimeController,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Open Time',
                                  prefixIcon: Icon(
                                    Icons.access_time_rounded,
                                    size: 20,
                                  ),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              final current = _parseToTimeOfDay(
                                _closeTimeController.text,
                                const TimeOfDay(hour: 23, minute: 30),
                              );
                              _pickTimeDialog(
                                controller: _closeTimeController,
                                title: 'Select Closing Time',
                                initialTime: current,
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: IgnorePointer(
                              child: TextField(
                                controller: _closeTimeController,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Close Time',
                                  prefixIcon: Icon(
                                    Icons.nightlight_round,
                                    size: 20,
                                  ),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ─── 5. Delivery / Pickup Note ───────────────────────
                    TextField(
                      controller: _pickupNoteController,
                      decoration: const InputDecoration(
                        labelText: 'Pickup / Delivery Note',
                        hintText: 'e.g. Pickup from Gate 3',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ─── 6. Contact / WhatsApp Number ───────────────────
                    TextField(
                      controller: _contactController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact / WhatsApp Number',
                        hintText: '10-digit mobile number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        prefixText: '+91 ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ─── Action Buttons ─────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _onCreateShop,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Create Shop',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
