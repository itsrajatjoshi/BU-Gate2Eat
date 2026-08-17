// BU Gate2Eat — Shopkeeper Panel
// Add Content Modal (Client-Side Auto-Compression <= 300KB & Safe Upload Flow)

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers.dart';
import '../../../../models/category_model.dart';
import '../../../../models/menu_item_model.dart';
import '../../../../services/image_optimization_service.dart';

class AddContentModal extends ConsumerStatefulWidget {
  const AddContentModal({
    required this.shopId,
    required this.categories,
    super.key,
  });

  final String shopId;
  final List<Category> categories;

  static Future<void> show(
    BuildContext context, {
    required String shopId,
    required List<Category> categories,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AddContentModal(shopId: shopId, categories: categories),
    );
  }

  @override
  ConsumerState<AddContentModal> createState() => _AddContentModalState();
}

class _AddContentModalState extends ConsumerState<AddContentModal> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _customCategoryController =
      TextEditingController();

  String _selectedCategory = 'Momos';
  bool _isOtherCategory = false;
  bool _isVeg = true;
  bool _isLoading = false;
  bool _isOptimizingImage = false;

  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  int? _selectedImageSizeBytes;
  String? _imageError;

  static const List<String> _defaultCategories = [
    'Momos',
    'Pizzas',
    'Snacks & Fast Food',
    'Burgers',
    'Thalis & Meals',
    'Desserts',
    'Beverages',
    'Chinese',
    'South Indian',
    'Rolls & Wraps',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.categories.isNotEmpty) {
      final firstValid = widget.categories
          .where((c) => c.id != 'all' && c.name.isNotEmpty)
          .map((c) => c.name)
          .firstOrNull;
      if (firstValid != null) {
        _selectedCategory = firstValid;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _detailsController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _isOptimizingImage = true;
          _imageError = null;
        });

        debugPrint('🔄 IMAGE OPTIMIZATION START (Menu Item)');
        final rawBytes = await picked.readAsBytes();

        // Automatically resize & compress to <= 300 KB on background isolate
        final optimized = await ImageOptimizationService.optimizeImageBytes(
          originalBytes: rawBytes,
          type: ImageTargetType.menuItem,
        );

        debugPrint('✅ IMAGE OPTIMIZATION COMPLETE');
        debugPrint(
          '📸 OPTIMIZED SIZE: ${(optimized.lengthInBytes / 1024).toStringAsFixed(1)} KB',
        );

        if (mounted) {
          setState(() {
            _selectedImageBytes = optimized;
            _selectedImageName = picked.name;
            _selectedImageSizeBytes = optimized.lengthInBytes;
            _isOptimizingImage = false;
          });
        }
      }
    } catch (e, stack) {
      debugPrint('❌ IMAGE OPTIMIZATION ERROR: $e\n$stack');
      if (mounted) {
        setState(() {
          _isOptimizingImage = false;
          _imageError = 'Failed to process image. Please try again.';
        });
      }
    }
  }

  Future<void> _onAdd() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    final details = _detailsController.text.trim();
    final effectiveCategory = _isOtherCategory
        ? _customCategoryController.text.trim()
        : _selectedCategory;

    if (name.isEmpty || priceText.isEmpty || details.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fill in all compulsory fields (*).'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final price = int.tryParse(priceText);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid price.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (_isOtherCategory && effectiveCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please type the custom category name.'),
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
      String categoryId = '';

      // If user typed custom category via "+ Other", create it in Firestore
      if (_isOtherCategory) {
        final createdCategory = await firestoreService.createCustomCategory(
          widget.shopId,
          effectiveCategory,
        );
        categoryId = createdCategory.id;
      } else {
        // Find existing category ID or generate slug
        final matched = widget.categories
            .where(
              (c) => c.name.toLowerCase() == effectiveCategory.toLowerCase(),
            )
            .firstOrNull;
        if (matched != null) {
          categoryId = matched.id;
        } else {
          final createdCategory = await firestoreService.createCustomCategory(
            widget.shopId,
            effectiveCategory,
          );
          categoryId = createdCategory.id;
        }
      }

      // If image bytes selected from gallery, upload optimized bytes to Firebase Storage
      String imageUrl = '';
      if (_selectedImageBytes != null) {
        final uploaded = await firestoreService.uploadImage(
          shopId: widget.shopId,
          path: 'items',
          bytes: _selectedImageBytes!,
          fileName: '${name.toLowerCase().replaceAll(' ', '_')}.jpg',
        );
        if (uploaded != null) {
          imageUrl = uploaded;
        }
      }

      final itemId =
          'item_${DateTime.now().millisecondsSinceEpoch}_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';

      final newItem = MenuItem(
        id: itemId,
        name: name,
        details: details,
        price: price,
        imageUrl: imageUrl,
        categoryId: categoryId,
        isVeg: _isVeg,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 99,
      );

      debugPrint('📝 FIRESTORE UPDATE START -> shops/${widget.shopId}/menuItems/$itemId');
      await firestoreService.addMenuItem(widget.shopId, newItem);
      debugPrint('✅ FIRESTORE UPDATE COMPLETE');

      // Invalidate Riverpod providers to refresh menu & categories instantly
      ref.invalidate(shopMenuItemsProvider(widget.shopId));
      ref.invalidate(shopCategoriesProvider(widget.shopId));

      if (mounted) {
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
                    '"$name" added to menu under "$effectiveCategory"!',
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
      debugPrint('🎉 SAVE COMPLETE');
    } catch (e, stack) {
      debugPrint('❌ SAVE ERROR: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add item: $e'),
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
        debugPrint('🔄 LOADING RESET: _isLoading = false');
      }
    }
  }

  List<String> _getAllCategoryOptions() {
    final set = <String>{};
    for (final c in widget.categories) {
      if (c.id != 'all' && c.name.isNotEmpty) {
        set.add(c.name);
      }
    }
    for (final def in _defaultCategories) {
      set.add(def);
    }
    return set.toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;
    final allCategories = _getAllCategoryOptions();

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
                        Icons.add_circle_outline_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add New Menu Item',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 19,
                                  ),
                        ),
                        Text(
                          'Item will be visible on shop menu immediately',
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

            // ─── 1. Image Upload Section ──────────────────────────────────
            Row(
              children: [
                Text(
                  'Item Image',
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
                    'Auto-Optimized ≤ 300 KB',
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
                      'Optimizing photo for fast loading...',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            else if (_selectedImageBytes != null) ...[
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
                        _selectedImageBytes!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedImageName ?? 'Uploaded Food Image',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Optimized: ${((_selectedImageSizeBytes ?? 0) / 1024).toStringAsFixed(1)} KB (≤ 300 KB limit)',
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
                                _selectedImageBytes = null;
                                _selectedImageName = null;
                                _selectedImageSizeBytes = null;
                                _imageError = null;
                              });
                            },
                    ),
                  ],
                ),
              ),
            ] else ...[
              InkWell(
                onTap: _isLoading ? null : _pickImage,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _imageError != null
                          ? AppColors.error
                          : (isDark
                              ? AppColors.darkDivider
                              : AppColors.divider),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 32,
                        color: _imageError != null
                            ? AppColors.error
                            : AppColors.primary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Upload Image from Gallery',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _imageError != null
                              ? AppColors.error
                              : AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Auto-compresses to ≤ 300 KB for fast delivery',
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
              ),
            ],

            if (_imageError != null) ...[
              const SizedBox(height: 4),
              Text(
                _imageError!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 14),

            // ─── 2. Item Name (Compulsory) ───────────────────────────────
            Text(
              'Item Name *',
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
                hintText: 'e.g. Paneer Steam Momos',
                prefixIcon: Icon(Icons.fastfood_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ─── 3. Category Selection (Options + Other Custom Type) ─────
            Text(
              'Category *',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),

            // Category Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...allCategories.map((cat) {
                  final isSelected =
                      !_isOtherCategory && _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    backgroundColor: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.surfaceVariant,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary),
                    ),
                    onSelected: _isLoading
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = cat;
                                _isOtherCategory = false;
                              });
                            }
                          },
                  );
                }),
                ChoiceChip(
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14),
                      SizedBox(width: 4),
                      Text('Other (Type Custom)'),
                    ],
                  ),
                  selected: _isOtherCategory,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  backgroundColor: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.surfaceVariant,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        _isOtherCategory ? FontWeight.bold : FontWeight.normal,
                    color: _isOtherCategory
                        ? AppColors.primary
                        : (isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary),
                  ),
                  onSelected: _isLoading
                      ? null
                      : (selected) {
                          setState(() {
                            _isOtherCategory = selected;
                          });
                        },
                ),
              ],
            ),

            // Custom Category Input Field
            if (_isOtherCategory) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customCategoryController,
                decoration: const InputDecoration(
                  hintText: 'Type new category name (e.g. Beverages, Rolls)',
                  prefixIcon: Icon(Icons.category_outlined),
                  isDense: true,
                ),
              ),
            ],

            const SizedBox(height: 14),

            // ─── 4. Price & Veg/Non-Veg (Compulsory) ──────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Price (₹) *',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'e.g. 70',
                          prefixIcon: Icon(Icons.currency_rupee_rounded),
                          isDense: true,
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
                        'Food Type *',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: _isVeg
                                      ? AppColors.vegGreen
                                      : AppColors.nonVegRed,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isVeg ? 'Veg' : 'Non-Veg',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _isVeg
                                        ? AppColors.vegGreen
                                        : AppColors.nonVegRed,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: _isVeg,
                              activeColor: AppColors.vegGreen,
                              inactiveThumbColor: AppColors.nonVegRed,
                              inactiveTrackColor: AppColors.nonVegRed
                                  .withValues(alpha: 0.3),
                              onChanged: _isLoading
                                  ? null
                                  : (val) => setState(() => _isVeg = val),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ─── 5. Portion / Description (Compulsory) ────────────────────
            Text(
              'Portion / Description *',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _detailsController,
              decoration: const InputDecoration(
                hintText: 'e.g. 8 Pieces / Served fresh with special sauces',
                prefixIcon: Icon(Icons.info_outline_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 22),

            // ─── 6. Action Button ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_isLoading || _isOptimizingImage) ? null : _onAdd,
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
                        'Add Item to Menu',
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
