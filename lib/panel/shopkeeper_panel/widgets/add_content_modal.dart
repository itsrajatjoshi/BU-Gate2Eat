// BU Gate2Eat — Shopkeeper Panel
// Add Content Modal (Client-Side Auto-Compression <= 300KB & Universal Options Support)

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers.dart';
import '../../../../models/category_model.dart';
import '../../../../models/menu_item_model.dart';
import '../../../../services/image_optimization_service.dart';

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
    required = (newType != OptionGroupType.extra);
    for (final opt in options) {
      if (newType == OptionGroupType.fixed) {
        opt.pricingType = OptionPricingType.fixedPrice;
      } else if (newType == OptionGroupType.choice) {
        opt.pricingType = OptionPricingType.selectionOnly;
        opt.priceController.text = '';
      } else if (newType == OptionGroupType.extra) {
        opt.pricingType = OptionPricingType.priceAdjustment;
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

  // ── Universal Options State ──────────────────────────────────────────────
  bool _hasOptions = false;
  final List<_EditableOptionGroup> _optionGroups = [];

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

  bool get _hasFixedPriceOption {
    if (!_hasOptions) return false;
    return _optionGroups.any((g) => g.groupType == OptionGroupType.fixed);
  }

  Future<void> _onAdd() async {
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
            optPrice = 0;
            pricingType = OptionPricingType.selectionOnly;
          } else if (group.groupType == OptionGroupType.fixed) {
            pricingType = OptionPricingType.fixedPrice;
            final parsed = int.tryParse(optPriceText);
            if (parsed == null || parsed <= 0) {
              _showErrorSnackBar('Fixed price for "$optName" in "$groupName" must be greater than 0.');
              return;
            }
            optPrice = parsed;
          } else {
            // OptionGroupType.extra
            pricingType = OptionPricingType.priceAdjustment;
            final parsed = int.tryParse(optPriceText);
            if (parsed == null || parsed < 0) {
              _showErrorSnackBar('Extra price for "$optName" in "$groupName" cannot be negative.');
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
            required: group.groupType != OptionGroupType.extra,
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
          id: '',
          name: name,
          details: details,
          price: 0,
          imageUrl: '',
          categoryId: '',
          isVeg: _isVeg,
          isAvailable: true,
          isRecommended: false,
          sortOrder: 0,
          optionGroups: constructedOptionGroups,
        );
        effectivePrice = dummyItem.startingPrice;
      }
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
        price: effectivePrice,
        imageUrl: imageUrl,
        categoryId: categoryId,
        isVeg: _isVeg,
        isAvailable: true,
        isRecommended: false,
        sortOrder: 99,
        optionGroups: constructedOptionGroups,
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
        _showErrorSnackBar('Failed to add item: $e');
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
                            hintText: 'e.g. 70',
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
            const SizedBox(height: 14),

            // ─── 6. Universal Options Toggle ──────────────────────────────
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

            // ─── 7. Option Groups Configuration Section (When ON) ─────────
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

            const SizedBox(height: 22),

            // ─── 8. Action Button ─────────────────────────────────────────
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

          // Group Type Selector: [ Fixed ] [ Choice ] [ Extra ]
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
                    const SizedBox(width: 6),
                    _buildGroupTypePill(group, OptionGroupType.choice, 'Choice', Icons.check_circle_outline_rounded, isDark),
                    const SizedBox(width: 6),
                    _buildGroupTypePill(group, OptionGroupType.extra, 'Extra', Icons.add_circle_outline_rounded, isDark),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Options Header
          Text(
            group.groupType == OptionGroupType.fixed
                ? 'Fixed Price Options (e.g. Small ₹40, Large ₹70):'
                : group.groupType == OptionGroupType.choice
                    ? 'Choices (e.g. With Sauce, Without Sauce — ₹0):'
                    : 'Extras (e.g. Cheese +₹10, Extra Patty +₹30 — Optional):',
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
                            : group.groupType == OptionGroupType.choice
                                ? 'e.g. With Sauce'
                                : 'e.g. Extra Cheese',
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

                  // Option Price Input (or No Price badge for Choice)
                  if (group.groupType == OptionGroupType.choice) ...[
                    Expanded(
                      flex: 4,
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkDivider
                                : AppColors.divider,
                          ),
                        ),
                        child: Text(
                          'No price (₹0)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: option.priceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          hintText: group.groupType == OptionGroupType.extra ? 'Extra' : 'Price',
                          prefixText: group.groupType == OptionGroupType.extra ? '+₹' : '₹',
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
                  ],

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
