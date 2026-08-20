// BU Gate2Eat — Shopkeeper Panel
// Edit Shop Modal (Auto-Compression <= 800KB & Direct Firebase Storage Upload Flow)

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers.dart';
import '../../../../models/shop_model.dart';
import '../../../../services/image_optimization_service.dart';

class EditShopModal extends ConsumerStatefulWidget {
  const EditShopModal({required this.shop, super.key});

  final Shop shop;

  static Future<void> show(BuildContext context, Shop shop) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditShopModal(shop: shop),
    );
  }

  @override
  ConsumerState<EditShopModal> createState() => _EditShopModalState();
}

class _EditShopModalState extends ConsumerState<EditShopModal> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _openTimeController;
  late TextEditingController _closeTimeController;
  late TextEditingController _pickupNoteController;
  late TextEditingController _contactController;
  late bool _isClosedOverride;
  bool _isLoading = false;
  bool _isOptimizingImage = false;

  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedBannerBytes;
  int? _selectedBannerSizeBytes;
  String? _bannerError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.shop.name);
    _descController = TextEditingController(text: widget.shop.description);
    _openTimeController =
        TextEditingController(text: widget.shop.formattedOpenTime);
    _closeTimeController =
        TextEditingController(text: widget.shop.formattedCloseTime);
    _pickupNoteController =
        TextEditingController(text: widget.shop.deliveryNote);
    _contactController =
        TextEditingController(text: widget.shop.contactNumber);
    _isClosedOverride = widget.shop.isClosedOverride;
  }

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

  /// Converts a time string (e.g. "8:00 AM" or "08:00") into a TimeOfDay object.
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

  /// Shows Flutter's 12-hour AM/PM native time picker
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

        debugPrint('[BANNER] optimization started');
        final rawBytes = await picked.readAsBytes();

        // Automatically resize & compress to <= 800 KB on background isolate
        final optimized = await ImageOptimizationService.optimizeImageBytes(
          originalBytes: rawBytes,
          type: ImageTargetType.shopBanner,
        );

        debugPrint('[BANNER] optimization completed');
        debugPrint(
          '[BANNER] optimized size: ${(optimized.lengthInBytes / 1024).toStringAsFixed(1)} KB',
        );

        if (mounted) {
          setState(() {
            _selectedBannerBytes = optimized;
            _selectedBannerSizeBytes = optimized.lengthInBytes;
            _isOptimizingImage = false;
          });
        }
      }
    } catch (e, stack) {
      debugPrint('❌ [BANNER] optimization error: $e\n$stack');
      if (mounted) {
        setState(() {
          _isOptimizingImage = false;
          _bannerError = 'Failed to process image. Please try again.';
        });
      }
    }
  }

  Future<void> _onSave() async {
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
      String bannerUrl = widget.shop.bannerUrl;

      // If new banner was picked from gallery, upload optimized bytes to Firebase Storage
      if (_selectedBannerBytes != null) {
        debugPrint('[BANNER] upload started');
        final uploadedUrl = await firestoreService.uploadImage(
          shopId: widget.shop.id,
          path: 'banner',
          bytes: _selectedBannerBytes!,
          fileName: 'shop_banner.jpg',
        );
        debugPrint('[BANNER] upload completed');
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          bannerUrl = uploadedUrl;
          debugPrint('[BANNER] download URL received: $bannerUrl');
        }
      }

      debugPrint('[BANNER] Firestore update started');
      final formattedOpen = _openTimeController.text.trim().isEmpty
          ? '8:00 AM'
          : Shop.format12hr(_openTimeController.text.trim());
      final formattedClose = _closeTimeController.text.trim().isEmpty
          ? '11:30 PM'
          : Shop.format12hr(_closeTimeController.text.trim());

      await firestoreService.updateShop(widget.shop.id, {
        'name': name,
        'description': _descController.text.trim(),
        'openTime': formattedOpen,
        'closeTime': formattedClose,
        'deliveryNote': _pickupNoteController.text.trim(),
        'contactNumber': _contactController.text.trim(),
        'orderNumber': _contactController.text.trim(),
        'bannerUrl': bannerUrl,
        'isClosedOverride': _isClosedOverride,
      });
      debugPrint('[BANNER] Firestore update completed');
      debugPrint('[BANNER] SAVE SUCCESS');

      // Invalidate provider so home screen and shop detail refresh immediately
      ref.invalidate(shopsProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Shop details updated successfully!',
                    style: TextStyle(fontWeight: FontWeight.w500),
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
    } catch (e, stack) {
      debugPrint('❌ [BANNER] SAVE ERROR: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update shop: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + keyboardBottom),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.store_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Shop Details',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 19,
                                  ),
                        ),
                        Text(
                          'Changes will reflect on student app immediately',
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

            // ─── 1. Shop Banner Section ──────────────────────────────────
            Row(
              children: [
                Text(
                  'Shop Banner Photo',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
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
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Optimizing banner photo for high speed...',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                            'New Banner Photo Selected',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Optimized: ${((_selectedBannerSizeBytes ?? 0) / 1024).toStringAsFixed(1)} KB (≤ 800 KB)',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.error,
                        size: 20,
                      ),
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _selectedBannerBytes = null;
                                _selectedBannerSizeBytes = null;
                                _bannerError = null;
                              });
                            },
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _bannerError != null
                        ? AppColors.error
                        : (isDark ? AppColors.darkDivider : AppColors.divider),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: widget.shop.bannerUrl,
                        width: 72,
                        height: 52,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.store_rounded,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Banner Photo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap Change to pick a new photo',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: (_isLoading || _isOptimizingImage)
                          ? null
                          : _pickBanner,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_outlined, size: 14),
                      label: const Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_bannerError != null) ...[
              const SizedBox(height: 4),
              Text(
                _bannerError!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 14),

            // ─── 2. Shop Name (Compulsory) ───────────────────────────────
            Text(
              'Shop Name *',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'e.g. Rajat Shop',
                prefixIcon: Icon(Icons.store_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ─── 3. Description / Specialties (Compulsory) ───────────────
            Text(
              'Specialties / Subtitle *',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                hintText: 'e.g. Chinese, Fast Food, Snacks & Special Thalis',
                prefixIcon: Icon(Icons.description_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ─── 4. Timings: 12-Hour AM/PM Native Clock Pickers ──────────
            Text(
              'Shop Timings (12-Hour AM/PM) *',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _isLoading
                        ? null
                        : () {
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
                    borderRadius: BorderRadius.circular(12),
                    child: IgnorePointer(
                      child: TextField(
                        controller: _openTimeController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Opening Time',
                          hintText: '8:00 AM',
                          prefixIcon: Icon(Icons.access_time_rounded),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _isLoading
                        ? null
                        : () {
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
                    borderRadius: BorderRadius.circular(12),
                    child: IgnorePointer(
                      child: TextField(
                        controller: _closeTimeController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Closing Time',
                          hintText: '11:30 PM',
                          prefixIcon: Icon(Icons.access_time_filled_rounded),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ─── 5. Pickup Location / Delivery Note ──────────────────────
            Text(
              'Pickup Location / Note',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _pickupNoteController,
              decoration: const InputDecoration(
                hintText: 'e.g. Pickup from Gate 2 / Near Canteen',
                prefixIcon: Icon(Icons.location_on_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ─── 6. Contact Number ───────────────────────────────────────
            Text(
              'Contact Number',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _contactController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'e.g. 9876543210',
                prefixIcon: Icon(Icons.phone_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ─── 7. Shop Operational Status Toggle ───────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isClosedOverride
                      ? AppColors.error.withValues(alpha: 0.4)
                      : (isDark ? AppColors.darkDivider : AppColors.divider),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isClosedOverride
                                ? Icons.remove_circle_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 16,
                            color: _isClosedOverride
                                ? AppColors.error
                                : AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isClosedOverride
                                ? 'Manually Marked CLOSED'
                                : 'Shop Open & Accepting Orders',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _isClosedOverride
                                  ? AppColors.error
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isClosedOverride
                            ? 'Students will see "CLOSED NOW"'
                            : 'Students can place orders normally',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: !_isClosedOverride,
                    activeColor: AppColors.success,
                    inactiveThumbColor: AppColors.error,
                    inactiveTrackColor: AppColors.error.withValues(alpha: 0.3),
                    onChanged: _isLoading
                        ? null
                        : (val) => setState(() => _isClosedOverride = !val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ─── 8. Save Button ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed:
                    (_isLoading || _isOptimizingImage) ? null : _onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save Shop Details',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
