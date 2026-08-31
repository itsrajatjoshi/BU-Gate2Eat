// BU Gate2Eat — Shopkeeper Panel
// Edit Menu Item Modal (Client-Side Auto-Compression <= 300KB & Universal Options Support)

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers.dart';
import '../../../../models/category_model.dart';
import '../../../../models/menu_item_model.dart';
import '../../../../services/image_optimization_service.dart';
import 'delete_item_dialog.dart';

/// Helper model for editing an option in the local modal state.
class _EditableOption {
  _EditableOption({
    String name = '',
    String price = '',
    this.pricingType = OptionPricingType.fixedPrice,
    this.isDefault = false,
  })  : nameController = TextEditingController(text: name),
        priceController = TextEditingController(text: price);

  final TextEditingController nameController;
  final TextEditingController priceController;
  OptionPricingType pricingType;
  bool isDefault;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}

/// Helper model for editing an option group in the local modal state.
class _EditableOptionGroup {
  _EditableOptionGroup({
    String name = '',
    List<_EditableOption>? options,
    this.required = true,
    this.groupType = OptionGroupType.fixed,
  })  : nameController = TextEditingController(text: name),
        options = options ?? [];

  final TextEditingController nameController;
  final List<_EditableOption> options;
  bool required;
  OptionGroupType groupType;

  void setGroupType(OptionGroupType newType) {
    groupType = newType;
    if (newType == OptionGroupType.fixed) {
      required = true;
      for (final opt in options) {
        opt.pricingType = OptionPricingType.fixedPrice;
      }
    } else {
      // OptionGroupType.choice
      for (final opt in options) {
        final parsed = int.tryParse(opt.priceController.text.trim()) ?? 0;
        opt.pricingType = parsed > 0 ? OptionPricingType.priceAdjustment : OptionPricingType.selectionOnly;
      }
    }
  }

  void dispose() {
    nameController.dispose();
    for (final opt in options) {
      opt.dispose();
    }
  }
}

class EditMenuItemModal extends ConsumerStatefulWidget {
  const EditMenuItemModal({
    required this.shopId,
    required this.item,
    required this.categories,
    super.key,
  });

  final String shopId;
  final MenuItem item;
  final List<Category> categories;

  static Future<void> show(
    BuildContext context, {
    required String shopId,
    required MenuItem item,
    required List<Category> categories,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditMenuItemModal(
        shopId: shopId,
        item: item,
        categories: categories,
      ),
    );
  }

  @override
  ConsumerState<EditMenuItemModal> createState() => _EditMenuItemModalState();
}

class _EditMenuItemModalState extends ConsumerState<EditMenuItemModal> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _detailsController;
  late TextEditingController _customCategoryController;

  late String _selectedCategory;
  late bool _isOtherCategory;
  late bool _isVeg;
  late bool _isAvailable;

  // ── Universal Options State ──────────────────────────────────────────────
  late bool _hasOptions;
  final List<_EditableOptionGroup> _optionGroups = [];

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
    _nameController = TextEditingController(text: widget.item.name);
    _priceController =
        TextEditingController(text: widget.item.price.toString());
    _detailsController = TextEditingController(text: widget.item.details);
    _customCategoryController = TextEditingController();

    _isVeg = widget.item.isVeg;
    _isAvailable = widget.item.isAvailable;

    // Load existing option groups into editable state
    _hasOptions = widget.item.hasOptions;
    if (_hasOptions) {
      for (final group in widget.item.optionGroups) {
        final editableOptions = group.options
            .map((opt) => _EditableOption(
                  name: opt.name,
                  price: opt.pricingType == OptionPricingType.selectionOnly
                      ? ''
                      : opt.price.toString(),
                  pricingType: opt.pricingType,
                  isDefault: opt.isDefault,
                ))
            .toList();
        _optionGroups.add(
          _EditableOptionGroup(
            name: group.name,
            required: group.required,
            groupType: group.groupType,
            options: editableOptions,
          ),
        );
      }
    }

    final currentCat = widget.categories
        .where((c) => c.id == widget.item.categoryId)
        .firstOrNull;

    if (currentCat != null) {
      _selectedCategory = currentCat.name;
      _isOtherCategory = false;
    } else {
      final matchByName = widget.categories
          .where(
            (c) =>
                c.name.toLowerCase() == widget.item.categoryId.toLowerCase(),
          )
          .firstOrNull;
      if (matchByName != null) {
        _selectedCategory = matchByName.name;
        _isOtherCategory = false;
      } else {
        _selectedCategory = widget.item.categoryId;
        _isOtherCategory = false;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _detailsController.dispose();
    _customCategoryController.dispose();
    for (final group in _optionGroups) {
      group.dispose();
    }
    super.dispose();
  }

  void _addEmptyOptionGroup() {
    setState(() {
      _optionGroups.add(
        _EditableOptionGroup(
          name: '',
          groupType: OptionGroupType.fixed,
          options: [
            _EditableOption(name: '', price: '', pricingType: OptionPricingType.fixedPrice, isDefault: true),
            _EditableOption(name: '', price: '', pricingType: OptionPricingType.fixedPrice),
          ],
        ),
      );
    });
  }

  String _getEffectiveImageUrl(MenuItem item) {
    if (item.imageUrl.isNotEmpty) return item.imageUrl;

    final nameLower = item.name.toLowerCase();
    if (nameLower.contains('momo') || nameLower.contains('dumpling')) {
      if (nameLower.contains('fried')) {
        return 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=500&auto=format&fit=crop&q=80';
      }
      return 'https://images.unsplash.com/photo-1625246333195-78d9c38ad449?w=500&auto=format&fit=crop&q=80';
    }
    if (nameLower.contains('pizza')) {
      return 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=500&auto=format&fit=crop&q=80';
    }
    if (nameLower.contains('burger')) {
      return 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&auto=format&fit=crop&q=80';
    }
    if (nameLower.contains('shake') || nameLower.contains('coffee') || nameLower.contains('beverage')) {
      return 'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=500&auto=format&fit=crop&q=80';
    }
    if (nameLower.contains('chowmein') || nameLower.contains('noodle') || nameLower.contains('rice')) {
      return 'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=500&auto=format&fit=crop&q=80';
    }
    if (nameLower.contains('roll') || nameLower.contains('wrap') || nameLower.contains('paneer')) {
      return 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=500&auto=format&fit=crop&q=80';
    }
    return '';
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _isOptimizingImage = true;
          _imageError = null;
        });

        debugPrint('🔄 IMAGE OPTIMIZATION START (Menu Item Edit)');
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

  bool get _hasFixedPriceOption {
    if (!_hasOptions) return false;
    return _optionGroups.any((g) => g.groupType == OptionGroupType.fixed);
  }

  Future<void> _onSave() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    final details = _detailsController.text.trim();
    final effectiveCategory = _isOtherCategory
        ? _customCategoryController.text.trim()
        : _selectedCategory;

    // 1. Basic compulsory fields validation
    if (name.isEmpty || details.isEmpty) {
      _showErrorSnackBar('Please fill in all compulsory fields (*).');
      return;
    }

    if (_isOtherCategory && effectiveCategory.isEmpty) {
      _showErrorSnackBar('Please type the custom category name.');
      return;
    }

    int effectivePrice = 0;
    final constructedOptionGroups = <MenuItemOptionGroup>[];

    // 2. Options validation vs Normal price validation
    if (!_hasOptions) {
      if (priceText.isEmpty) {
        _showErrorSnackBar('Please enter a valid price.');
        return;
      }
      final parsedPrice = int.tryParse(priceText);
      if (parsedPrice == null || parsedPrice <= 0) {
        _showErrorSnackBar('Please enter a valid price greater than 0.');
        return;
      }
      effectivePrice = parsedPrice;
    } else {
      // Options are ON: validate groups and options
      if (_optionGroups.isEmpty) {
        _showErrorSnackBar('Please add at least one option group or turn options OFF.');
        return;
      }

      for (var gIdx = 0; gIdx < _optionGroups.length; gIdx++) {
        final group = _optionGroups[gIdx];
        final groupName = group.nameController.text.trim();
        if (groupName.isEmpty) {
          _showErrorSnackBar('Group #${gIdx + 1} name cannot be empty.');
          return;
        }

        if (group.options.isEmpty) {
          _showErrorSnackBar('Group "$groupName" must have at least one option.');
          return;
        }

        final constructedOptions = <MenuItemOption>[];
        for (var oIdx = 0; oIdx < group.options.length; oIdx++) {
          final opt = group.options[oIdx];
          final optName = opt.nameController.text.trim();
          final optPriceText = opt.priceController.text.trim();

          if (optName.isEmpty) {
            _showErrorSnackBar('Option #${oIdx + 1} in "$groupName" needs a name.');
            return;
          }

          int optPrice = 0;
          OptionPricingType pricingType;

          if (group.groupType == OptionGroupType.choice) {
            final parsed = int.tryParse(optPriceText);
            if (parsed != null && parsed > 0) {
              pricingType = OptionPricingType.priceAdjustment;
              optPrice = parsed;
            } else {
              pricingType = OptionPricingType.selectionOnly;
              optPrice = 0;
            }
          } else {
            // OptionGroupType.fixed
            pricingType = OptionPricingType.fixedPrice;
            final parsed = int.tryParse(optPriceText);
            if (parsed == null || parsed <= 0) {
              _showErrorSnackBar('Fixed price for "$optName" in "$groupName" must be greater than 0.');
              return;
            }
            optPrice = parsed;
          }

          constructedOptions.add(
            MenuItemOption(
              id: 'opt_${gIdx + 1}_${oIdx + 1}',
              name: optName,
              price: optPrice,
              pricingType: pricingType,
              isDefault: opt.isDefault,
            ),
          );
        }

        constructedOptionGroups.add(
          MenuItemOptionGroup(
            id: 'grp_${gIdx + 1}',
            name: groupName,
            required: group.groupType == OptionGroupType.fixed ? true : group.required,
            groupType: group.groupType,
            options: constructedOptions,
          ),
        );
      }

      // If no fixed-price group exists (only adjustment or selectionOnly), main price is required
      if (!_hasFixedPriceOption) {
        if (priceText.isEmpty) {
          _showErrorSnackBar('Please enter a base price for this item.');
          return;
        }
        final parsedPrice = int.tryParse(priceText);
        if (parsedPrice == null || parsedPrice <= 0) {
          _showErrorSnackBar('Please enter a valid base price greater than 0.');
          return;
        }
        effectivePrice = parsedPrice;
      } else {
        // Safe base price for Firestore backward compatibility
        final dummyItem = MenuItem(
          id: widget.item.id,
          name: name,
          details: details,
          price: 0,
          imageUrl: '',
          categoryId: '',
          isVeg: _isVeg,
          isAvailable: _isAvailable,
          isRecommended: widget.item.isRecommended,
          sortOrder: widget.item.sortOrder,
          optionGroups: constructedOptionGroups,
        );
        effectivePrice = dummyItem.startingPrice;
      }
    }

    setState(() => _isLoading = true);

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      String categoryId = '';

      // If category was changed to custom category via "+ Other"
      if (_isOtherCategory) {
        final createdCategory = await firestoreService.createCustomCategory(
          widget.shopId,
          effectiveCategory,
        );
        categoryId = createdCategory.id;
      } else {
        final matched = widget.categories
            .where(
              (c) =>
                  c.name.toLowerCase() == effectiveCategory.toLowerCase() ||
                  c.id.toLowerCase() == effectiveCategory.toLowerCase(),
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

      String imageUrl = widget.item.imageUrl;
      // If new image was picked from gallery, upload optimized bytes to Firebase Storage
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

      final updateMap = <String, dynamic>{
        'name': name,
        'price': effectivePrice,
        'details': details,
        'isVeg': _isVeg,
        'isAvailable': _isAvailable,
        'categoryId': categoryId,
        'imageUrl': imageUrl,
        'optionGroups': _hasOptions
            ? constructedOptionGroups.map((g) => g.toMap()).toList()
            : <Map<String, dynamic>>[], // Explicitly clear optionGroups when converting back to normal item
      };

      debugPrint('📝 FIRESTORE UPDATE START -> shops/${widget.shopId}/menuItems/${widget.item.id}');
      await firestoreService.updateMenuItem(widget.shopId, widget.item.id, updateMap);
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
                    '"$name" updated successfully!',
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
        _showErrorSnackBar('Failed to update item: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('🔄 LOADING RESET: _isLoading = false');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _onDelete() async {
    final confirmed = await DeleteItemDialog.show(
      context,
      widget.item,
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);
      try {
        await ref.read(firestoreServiceProvider).deleteMenuItem(
              widget.shopId,
              widget.item.id,
              imageUrl: widget.item.imageUrl,
            );

        ref.invalidate(shopMenuItemsProvider(widget.shopId));
        ref.invalidate(shopCategoriesProvider(widget.shopId));

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${widget.item.name}" deleted from menu.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Failed to delete item: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
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
    final currentImageUrl = _getEffectiveImageUrl(widget.item);

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
                        Icons.edit_note_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Menu Item',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 19,
                                  ),
                        ),
                        Text(
                          'Changes will be updated immediately',
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
                            _selectedImageName ?? 'New Uploaded Image',
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
            ] else if (currentImageUrl.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkDivider
                        : AppColors.divider,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: currentImageUrl,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.image, color: Colors.grey),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Image',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.item.imageUrl.isEmpty
                                ? 'Auto-assigned fallback'
                                : 'Uploaded',
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
                      onPressed: _isLoading ? null : _pickImage,
                      icon: const Icon(Icons.change_circle_outlined, size: 16),
                      label: const Text('Change', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
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
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkDivider
                              : AppColors.divider),
                    ),
                    onSelected: (selected) {
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
                  avatar: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('Other (Type Custom)'),
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
                  side: BorderSide(
                    color: _isOtherCategory
                        ? AppColors.primary
                        : (isDark
                            ? AppColors.darkDivider
                            : AppColors.divider),
                  ),
                  onSelected: (selected) {
                    setState(() {
                      _isOtherCategory = selected;
                    });
                  },
                ),
              ],
            ),

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
                if (_hasFixedPriceOption) ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Base Price (₹)',
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
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.6)
                                : AppColors.surfaceVariant.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? AppColors.darkDivider : AppColors.divider,
                            ),
                          ),
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 16,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Set by Option Sizes',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
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
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            hintText: 'e.g. 60',
                            prefixIcon: Icon(Icons.currency_rupee_rounded),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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

            // ─── 5. Availability Status Toggle ────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: !_isAvailable
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
                            _isAvailable
                                ? Icons.check_circle_outline_rounded
                                : Icons.remove_circle_outline_rounded,
                            size: 16,
                            color: _isAvailable
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isAvailable
                                ? 'Item Available (In Stock)'
                                : 'Out of Stock (Unavailable)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _isAvailable
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isAvailable
                            ? 'Students can see & order this item'
                            : 'Students will see "OUT OF STOCK"',
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
                    value: _isAvailable,
                    activeThumbColor: AppColors.success,
                    inactiveThumbColor: AppColors.error,
                    inactiveTrackColor: AppColors.error.withValues(alpha: 0.3),
                    onChanged: _isLoading
                        ? null
                        : (val) => setState(() => _isAvailable = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ─── 6. Portion / Description (Compulsory) ────────────────────
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
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g. 8 Pieces / Served fresh with spicy schezwan',
                prefixIcon: Icon(Icons.info_outline_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ─── 7. Universal Options Toggle ──────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasOptions
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : (isDark ? AppColors.darkDivider : AppColors.divider),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Does this item have options / sizes?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'e.g. Half / Full, Sizes, Dry / Gravy',
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
                  Switch(
                    value: _hasOptions,
                    activeColor: AppColors.primary,
                    onChanged: _isLoading
                        ? null
                        : (val) {
                            setState(() {
                              _hasOptions = val;
                              if (_hasOptions && _optionGroups.isEmpty) {
                                _addEmptyOptionGroup();
                              }
                            });
                          },
                  ),
                ],
              ),
            ),

            // ─── 8. Option Groups Configuration Section (When ON) ─────────
            if (_hasOptions) ...[
              const SizedBox(height: 14),
              ..._optionGroups.asMap().entries.map((entry) {
                final gIdx = entry.key;
                final group = entry.value;
                return _buildOptionGroupCard(group, gIdx, isDark);
              }),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _addEmptyOptionGroup,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Another Option Group'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ─── 9. Delete Item Button ────────────────────────────────────
            Center(
              child: TextButton.icon(
                onPressed: (_isLoading || _isOptimizingImage) ? null : _onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text(
                  'Delete Item from Menu',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ─── 10. Save Button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_isLoading || _isOptimizingImage) ? null : _onSave,
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
                        'Save Changes',
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

  Widget _buildOptionGroupCard(
    _EditableOptionGroup group,
    int gIdx,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Header Row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: group.nameController,
                  decoration: InputDecoration(
                    labelText: 'Option Group Name *',
                    hintText: 'e.g. Portion, Size, Preparation',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
                tooltip: 'Delete Group',
                onPressed: () {
                  setState(() {
                    final removed = _optionGroups.removeAt(gIdx);
                    removed.dispose();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Group Type Selector: [ Fixed ] [ Choice ]
          Row(
            children: [
              Text(
                'Group Type:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    _buildGroupTypePill(group, OptionGroupType.fixed, 'Fixed', Icons.payments_outlined, isDark),
                    const SizedBox(width: 8),
                    _buildGroupTypePill(group, OptionGroupType.choice, 'Choice', Icons.tune_rounded, isDark),
                  ],
                ),
              ),
            ],
          ),
          if (group.groupType == OptionGroupType.choice) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Required Selection?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => group.required = true),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: group.required
                          ? AppColors.primary
                          : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'YES (Mandatory)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: group.required ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() => group.required = false),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: !group.required
                          ? AppColors.primary
                          : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'NO (Optional)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: !group.required ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),

          // Options Header
          Text(
            group.groupType == OptionGroupType.fixed
                ? 'Fixed Price Options (e.g. Small ₹40, Large ₹70):'
                : 'Choice Options (0 = no surcharge, or enter +₹ adjustment):',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 6),

          // Options List
          ...group.options.asMap().entries.map((optEntry) {
            final oIdx = optEntry.key;
            final option = optEntry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  // Option Name
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: option.nameController,
                      decoration: InputDecoration(
                        hintText: group.groupType == OptionGroupType.fixed
                            ? 'e.g. Half, Full'
                            : 'e.g. With Sauce, Cheese',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 9,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Option Price Input
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: option.priceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        hintText: group.groupType == OptionGroupType.fixed ? 'Price' : '0 (optional)',
                        prefixText: group.groupType == OptionGroupType.fixed ? '₹' : '+₹',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 9,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),

                  // Delete Option Button
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.grey,
                    ),
                    tooltip: 'Delete Choice',
                    onPressed: group.options.length <= 1
                        ? null
                        : () {
                            setState(() {
                              final removed = group.options.removeAt(oIdx);
                              removed.dispose();
                            });
                          },
                  ),
                ],
              ),
            );
          }),

          // Add Option Button within Group
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  group.options.add(
                    _EditableOption(
                      name: '',
                      price: '',
                      pricingType: group.groupType == OptionGroupType.fixed
                          ? OptionPricingType.fixedPrice
                          : group.groupType == OptionGroupType.choice
                              ? OptionPricingType.selectionOnly
                              : OptionPricingType.priceAdjustment,
                    ),
                  );
                });
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
              label: const Text(
                'Add Choice',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTypePill(
    _EditableOptionGroup group,
    OptionGroupType type,
    String label,
    IconData icon,
    bool isDark,
  ) {
    final isSelected = group.groupType == type;
    final primaryColor = type == OptionGroupType.fixed
        ? AppColors.primary
        : type == OptionGroupType.choice
            ? Colors.teal
            : Colors.orange;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              group.setGroupType(type);
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.15)
                  : (isDark ? AppColors.darkSurface : Colors.white),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? primaryColor
                    : (isDark ? AppColors.darkDivider : Colors.grey.shade300),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: isSelected
                      ? primaryColor
                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? primaryColor
                        : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
