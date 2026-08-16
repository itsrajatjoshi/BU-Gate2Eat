// BU Gate2Eat — Shopkeeper Panel
// Edit Shop Modal (Connected to Firestore & Firebase Storage with 12-hour AM/PM Time Pickers)

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers.dart';
import '../../../../models/shop_model.dart';

class EditShopModal extends ConsumerStatefulWidget {
  const EditShopModal({
    required this.shop,
    super.key,
  });

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

  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedBannerBytes;
  int? _selectedBannerSizeBytes;
  String? _bannerError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.shop.name);
    _descController = TextEditingController(text: widget.shop.description);
    _openTimeController = TextEditingController(
      text: widget.shop.formattedOpenTime.isNotEmpty
          ? widget.shop.formattedOpenTime
          : '8:00 AM',
    );
    _closeTimeController = TextEditingController(
      text: widget.shop.formattedCloseTime.isNotEmpty
          ? widget.shop.formattedCloseTime
          : '11:30 PM',
    );
    _pickupNoteController =
        TextEditingController(text: widget.shop.deliveryNote);
    _contactController = TextEditingController(text: widget.shop.contactNumber);
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

  Future<void> _pickTime({required bool isOpenTime}) async {
    final currentText =
        isOpenTime ? _openTimeController.text : _closeTimeController.text;
    final minutes = Shop.parseTimeToMinutes(
      currentText,
      defaultMinutes: isOpenTime ? 8 * 60 : 23 * 60 + 30,
    );
    final initialTime = TimeOfDay(
      hour: minutes ~/ 60,
      minute: minutes % 60,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: isOpenTime ? 'Select Opening Time' : 'Select Closing Time',
    );

    if (picked != null) {
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      final hour12 = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final minute = picked.minute.toString().padLeft(2, '0');
      final formatted = '$hour12:$minute $period';

      setState(() {
        if (isOpenTime) {
          _openTimeController.text = formatted;
        } else {
          _closeTimeController.text = formatted;
        }
      });
    }
  }

  Future<void> _pickBanner() {
    return _picker.pickImage(source: ImageSource.gallery).then((picked) async {
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final size = bytes.lengthInBytes;
        const maxBytes = 1024 * 1024; // 1 MB

        if (size > maxBytes) {
          final sizeMb = (size / (1024 * 1024)).toStringAsFixed(2);
          setState(() {
            _selectedBannerBytes = null;
            _selectedBannerSizeBytes = null;
            _bannerError =
                'Image size ($sizeMb MB) exceeds 1MB limit. Please choose an image under 1MB.';
          });
        } else {
          setState(() {
            _selectedBannerBytes = bytes;
            _selectedBannerSizeBytes = size;
            _bannerError = null;
          });
        }
      }
    });
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

      // If new banner was picked from gallery, upload to Firebase Storage
      if (_selectedBannerBytes != null) {
        final uploadedUrl = await firestoreService.uploadImage(
          shopId: widget.shop.id,
          path: 'banner',
          bytes: _selectedBannerBytes!,
          fileName: 'shop_banner.jpg',
        );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          bannerUrl = uploadedUrl;
        }
      }

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
        'bannerUrl': bannerUrl,
        'isClosedOverride': _isClosedOverride,
      });

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
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
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

            // Header Row
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
                        Icons.storefront_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Shop Info',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 19,
                                  ),
                        ),
                        Text(
                          'Update shop banner, timings & details',
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

            // ─── 1. Shop Banner Image (Change from Phone Gallery / Max 1MB) ──
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
                    'Max 1 MB',
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

            // Banner Image Preview Box
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _bannerError != null
                      ? AppColors.error
                      : (isDark ? AppColors.darkDivider : AppColors.divider),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _selectedBannerBytes != null
                        ? Image.memory(
                            _selectedBannerBytes!,
                            fit: BoxFit.cover,
                          )
                        : (widget.shop.bannerUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.shop.bannerUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: isDark
                                      ? AppColors.darkSurfaceVariant
                                      : Colors.grey[200],
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: isDark
                                      ? AppColors.darkSurfaceVariant
                                      : Colors.grey[200],
                                  child: const Icon(Icons.store_rounded),
                                ),
                              )
                            : Container(
                                color: isDark
                                    ? AppColors.darkSurfaceVariant
                                    : Colors.grey[200],
                                child: const Icon(Icons.store_rounded),
                              )),
                  ),

                  // Overlay Button to Change Banner
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickBanner,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.75),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded, size: 14),
                      label: Text(
                        _selectedBannerBytes != null
                            ? 'Change Banner'
                            : 'Upload / Change',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  if (_selectedBannerBytes != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'New Photo (${((_selectedBannerSizeBytes ?? 0) / 1024).toStringAsFixed(1)} KB)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

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

            // ─── 2. Temporary Open / Closed Status Override ───────────────
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
                                ? Icons.do_not_disturb_on_rounded
                                : Icons.access_time_rounded,
                            size: 16,
                            color: _isClosedOverride
                                ? AppColors.error
                                : AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isClosedOverride
                                ? 'Temporarily Closed (Override)'
                                : 'Open based on Schedule',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _isClosedOverride
                                  ? AppColors.error
                                  : (isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isClosedOverride
                            ? 'Shop is marked closed for emergency/holiday'
                            : 'Normal schedule: ${_openTimeController.text} – ${_closeTimeController.text}',
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
                    activeThumbColor: AppColors.success,
                    inactiveThumbColor: AppColors.error,
                    inactiveTrackColor: AppColors.error.withValues(alpha: 0.3),
                    onChanged: _isLoading
                        ? null
                        : (val) => setState(() => _isClosedOverride = !val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ─── 3. Shop Name ────────────────────────────────────────────
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
                prefixIcon: Icon(Icons.storefront_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ─── 4. Description ──────────────────────────────────────────
            Text(
              'Cuisine & Description',
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

            // ─── 5. Open & Close Timings (12-hour AM/PM Pickers) ──────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Opening Time',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _isLoading
                            ? null
                            : () => _pickTime(isOpenTime: true),
                        borderRadius: BorderRadius.circular(12),
                        child: IgnorePointer(
                          child: TextField(
                            controller: _openTimeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              hintText: '8:00 AM',
                              prefixIcon: Icon(Icons.access_time_rounded),
                              suffixIcon:
                                  Icon(Icons.arrow_drop_down_rounded, size: 22),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Closing Time',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _isLoading
                            ? null
                            : () => _pickTime(isOpenTime: false),
                        borderRadius: BorderRadius.circular(12),
                        child: IgnorePointer(
                          child: TextField(
                            controller: _closeTimeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              hintText: '11:30 PM',
                              prefixIcon:
                                  Icon(Icons.access_time_filled_rounded),
                              suffixIcon:
                                  Icon(Icons.arrow_drop_down_rounded, size: 22),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ─── 6. Delivery / Pickup Note ────────────────────────────────
            Text(
              'Pickup Location / Delivery Note',
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
                hintText: 'e.g. Pickup from Gate 2',
                prefixIcon: Icon(Icons.location_on_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ─── 7. Contact Number ───────────────────────────────────────
            Text(
              'Contact / WhatsApp Order Number',
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
                hintText: '8295643910',
                prefixIcon: Icon(Icons.phone_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 22),

            // ─── 8. Save Button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onSave,
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
