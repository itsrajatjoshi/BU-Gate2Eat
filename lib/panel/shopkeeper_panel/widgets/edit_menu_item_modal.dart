// BU Gate2Eat — Shopkeeper Panel
// Edit Menu Item Modal (Connected to Firestore & Firebase Storage)

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers.dart';
import '../../../../models/category_model.dart';
import '../../../../models/menu_item_model.dart';
import 'delete_item_dialog.dart';

class EditMenuItemModal extends ConsumerStatefulWidget {
  const EditMenuItemModal({
    required this.item,
    required this.categories,
    this.shopId = 'rajat_shop',
    super.key,
  });

  final MenuItem item;
  final List<Category> categories;
  final String shopId;

  static Future<void> show(
    BuildContext context, {
    required MenuItem item,
    required List<Category> categories,
    String shopId = 'rajat_shop',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditMenuItemModal(
        item: item,
        categories: categories,
        shopId: shopId,
      ),
    );
  }

  @override
  ConsumerState<EditMenuItemModal> createState() => _EditMenuItemModalState();
}

class _EditMenuItemModalState extends ConsumerState<EditMenuItemModal> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _detailsController;
  final _customCategoryController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  int? _selectedImageSizeBytes;
  String? _imageError;

  late bool _isVeg;
  late bool _isAvailable;
  late String _selectedCategory;
  bool _isOtherCategory = false;
  bool _isLoading = false;

  static const List<String> _defaultCategories = [
    'Momos',
    'Pizzas',
    'Burgers',
    'Biryani',
    'Thali',
    'Snacks',
    'Rolls',
    'Noodles',
    'Beverages',
    'Desserts',
    'Ice Cream',
    'Sushi',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _priceController =
        TextEditingController(text: widget.item.price.toStringAsFixed(0));
    _detailsController = TextEditingController(text: widget.item.details);
    _isVeg = widget.item.isVeg;
    _isAvailable = widget.item.isAvailable;

    // Match existing category
    final matchedCat = widget.categories
        .where(
          (c) =>
              c.id.toLowerCase() == widget.item.categoryId.toLowerCase() ||
              c.name.toLowerCase() == widget.item.categoryId.toLowerCase(),
        )
        .map((c) => c.name)
        .firstOrNull;

    if (matchedCat != null) {
      _selectedCategory = matchedCat;
    } else {
      final capCat = widget.item.categoryId.isNotEmpty
          ? widget.item.categoryId[0].toUpperCase() +
              widget.item.categoryId.substring(1)
          : 'Momos';
      _selectedCategory = capCat;
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

  String _getEffectiveImageUrl(MenuItem item) {
    if (item.imageUrl.isNotEmpty) return item.imageUrl;

    final nameLower = item.name.toLowerCase();
    if (nameLower.contains('momo') || nameLower.contains('dumpling')) {
      if (nameLower.contains('fried')) {
        return 'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=500&auto=format&fit=crop&q=80';
      }
      return 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('noodle') ||
        nameLower.contains('chow') ||
        nameLower.contains('maggi')) {
      return 'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('burger')) {
      return 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('paneer') || nameLower.contains('curry')) {
      return 'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('roll') ||
        nameLower.contains('wrap') ||
        nameLower.contains('frankie')) {
      return 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=500&auto=format&fit=crop&q=80';
    } else if (nameLower.contains('pizza')) {
      return 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=500&auto=format&fit=crop&q=80';
    }

    final fallbacks = [
      'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=500&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1541696432-82c6da8ce7bf?w=500&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1612927601601-6638404737ce?w=500&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?w=500&auto=format&fit=crop&q=80',
    ];
    return fallbacks[item.id.hashCode.abs() % fallbacks.length];
  }

  Future<void> _pickImage() {
    return _picker.pickImage(source: ImageSource.gallery).then((picked) async {
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final size = bytes.lengthInBytes;
        const maxBytes = 1024 * 1024; // 1 MB

        if (size > maxBytes) {
          final sizeMb = (size / (1024 * 1024)).toStringAsFixed(2);
          setState(() {
            _selectedImageBytes = null;
            _selectedImageName = null;
            _selectedImageSizeBytes = null;
            _imageError =
                'Image size ($sizeMb MB) exceeds 1MB limit. Please choose a smaller image.';
          });
        } else {
          setState(() {
            _selectedImageBytes = bytes;
            _selectedImageName = picked.name;
            _selectedImageSizeBytes = size;
            _imageError = null;
          });
        }
      }
    });
  }

  Future<void> _onSave() async {
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
      String categoryId = widget.item.categoryId;

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
              (c) => c.name.toLowerCase() == effectiveCategory.toLowerCase(),
            )
            .firstOrNull;
        if (matched != null) {
          categoryId = matched.id;
        }
      }

      String imageUrl = widget.item.imageUrl;
      // If new image was picked from gallery, upload to Firebase Storage
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

      await firestoreService.updateMenuItem(widget.shopId, widget.item.id, {
        'name': name,
        'price': price,
        'details': details,
        'isVeg': _isVeg,
        'isAvailable': _isAvailable,
        'categoryId': categoryId,
        'imageUrl': imageUrl,
      });

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
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update item: $e'),
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

  void _onDelete() {
    DeleteItemDialog.show(context, widget.item).then((confirmed) async {
      if (confirmed == true && mounted) {
        setState(() => _isLoading = true);
        try {
          final firestoreService = ref.read(firestoreServiceProvider);
          await firestoreService.deleteMenuItem(widget.shopId, widget.item.id);
          ref.invalidate(shopMenuItemsProvider(widget.shopId));

          if (mounted) {
            Navigator.pop(context); // Close edit modal
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '"${widget.item.name}" deleted from menu.',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.error,
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
                content: Text('Failed to delete item: $e'),
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
    });
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
    if (_selectedCategory.isNotEmpty) {
      set.add(_selectedCategory);
    }
    return set.toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;
    final allCategories = _getAllCategoryOptions();
    final currentExistingImageUrl = _getEffectiveImageUrl(widget.item);

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
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit Menu Item',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'All details marked with * are compulsory',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── 1. Image Upload / Change (Local storage / Max 1MB) ──────
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

            if (_selectedImageBytes != null) ...[
              // New image preview with change / revert options
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _selectedImageBytes!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedImageName ?? 'New Uploaded Photo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Size: ${((_selectedImageSizeBytes ?? 0) / 1024).toStringAsFixed(1)} KB (Under 1MB)',
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
                        Icons.refresh_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      tooltip: 'Choose Different Image',
                      onPressed: _isLoading ? null : _pickImage,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.undo_rounded,
                        color: AppColors.textHint,
                        size: 20,
                      ),
                      tooltip: 'Revert to Original Image',
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
              // Current image preview with Change Image button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _imageError != null
                        ? AppColors.error
                        : (isDark ? AppColors.darkDivider : AppColors.divider),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: currentExistingImageUrl,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.fastfood_rounded,
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
                            'Current Item Photo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap button to change from gallery',
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
                hintText: 'e.g. Veg Steam Momos',
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

            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...allCategories.map((cat) {
                  final isSelected = !_isOtherCategory &&
                      _selectedCategory.toLowerCase() == cat.toLowerCase();
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
                  label: const Text('+ Other (Type Custom)'),
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
                        : (isDark ? AppColors.darkDivider : AppColors.divider),
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
                autofocus: true,
                decoration: const InputDecoration(
                  hintText:
                      'Type custom category (e.g. Sushi, Ice Cream, Beverages)',
                  prefixIcon: Icon(Icons.add_circle_outline_rounded),
                  isDense: true,
                ),
              ),
            ],

            const SizedBox(height: 14),

            // ─── 4. Price & Food Type (Veg / Non-Veg) ─────────────────────
            Row(
              children: [
                Expanded(
                  flex: 3,
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
                          hintText: '90',
                          prefixText: '₹ ',
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 3,
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
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkDivider
                                : AppColors.divider,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _isVeg ? 'Veg' : 'Non-Veg',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _isVeg
                                    ? AppColors.vegGreen
                                    : AppColors.nonVegRed,
                              ),
                            ),
                            Switch(
                              value: _isVeg,
                              activeThumbColor: AppColors.vegGreen,
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

            // ─── 6. Availability Status Toggle ────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Item In Stock / Available',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _isAvailable
                            ? 'Customers can order this item'
                            : 'Item marked Out of Stock',
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
                    onChanged: _isLoading
                        ? null
                        : (val) => setState(() => _isAvailable = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ─── 7. Action Buttons (Save Changes + Delete) ────────────────
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _onDelete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side:
                          const BorderSide(color: AppColors.error, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text(
                      'Delete',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
          ],
        ),
      ),
    );
  }
}
