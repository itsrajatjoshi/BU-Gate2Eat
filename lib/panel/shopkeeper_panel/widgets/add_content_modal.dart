// BU Gate2Eat — Shopkeeper Panel
// Add Item Modal (Single Unified Form with Image Picker Max 1MB & Category Options + Other)
// UI/UX Prototype ONLY — No Backend Modification

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../models/category_model.dart';

class AddContentModal extends StatefulWidget {
  const AddContentModal({
    required this.categories,
    super.key,
  });

  final List<Category> categories;

  static Future<void> show(
    BuildContext context, {
    required List<Category> categories,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddContentModal(categories: categories),
    );
  }

  @override
  State<AddContentModal> createState() => _AddContentModalState();
}

class _AddContentModalState extends State<AddContentModal> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _detailsController = TextEditingController();
  final _customCategoryController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  int? _selectedImageSizeBytes;
  String? _imageError;

  bool _isVeg = true;
  String _selectedCategory = 'Momos';
  bool _isOtherCategory = false;

  // Curated category options
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
            _imageError = 'Image size ($sizeMb MB) exceeds 1MB limit. Please choose a smaller image.';
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

  void _onAdd() {
    final name = _nameController.text.trim();
    final price = _priceController.text.trim();
    final details = _detailsController.text.trim();
    final effectiveCategory = _isOtherCategory
        ? _customCategoryController.text.trim()
        : _selectedCategory;

    if (name.isEmpty || price.isEmpty || details.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fill in all compulsory fields (*).'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

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
                'UI Prototype: "$name" added under "$effectiveCategory" (No backend write)',
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
                      'Add New Menu Item',
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
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
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

            // ─── 1. Image Upload (Local storage / Phone Gallery / Max 1MB) ───
            Row(
              children: [
                Text(
                  'Item Image',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
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
                            _selectedImageName ?? 'Uploaded Food Image',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Size: ${((_selectedImageSizeBytes ?? 0) / 1024).toStringAsFixed(1)} KB (Under 1MB limit)',
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
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                      onPressed: () {
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
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _imageError != null
                          ? AppColors.error
                          : (isDark ? AppColors.darkDivider : AppColors.divider),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 32,
                        color: _imageError != null ? AppColors.error : AppColors.primary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Upload Image from Gallery / Phone',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _imageError != null ? AppColors.error : AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'PNG, JPG or WEBP up to 1 MB',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
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
                style: const TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600),
              ),
            ],

            const SizedBox(height: 14),

            // ─── 2. Item Name (Compulsory) ───────────────────────────────
            Text(
              'Item Name *',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
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
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),

            // Category Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...allCategories.map((cat) {
                  final isSelected = !_isOtherCategory && _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkDivider : AppColors.divider),
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

                // "+ Other" Chip
                ChoiceChip(
                  avatar: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('+ Other (Type Custom)'),
                  selected: _isOtherCategory,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: _isOtherCategory ? FontWeight.bold : FontWeight.normal,
                    color: _isOtherCategory
                        ? AppColors.primary
                        : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
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

            // Animated Custom Category Text Field (Visible when Other is chosen)
            if (_isOtherCategory) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customCategoryController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Type custom category (e.g. Sushi, Ice Cream, Beverages)',
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
                              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
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
                              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? AppColors.darkDivider : AppColors.divider,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _isVeg ? 'Veg' : 'Non-Veg',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _isVeg ? AppColors.vegGreen : AppColors.nonVegRed,
                              ),
                            ),
                            Switch(
                              value: _isVeg,
                              activeThumbColor: AppColors.vegGreen,
                              inactiveThumbColor: AppColors.nonVegRed,
                              inactiveTrackColor: AppColors.nonVegRed.withValues(alpha: 0.3),
                              onChanged: (val) => setState(() => _isVeg = val),
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
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
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
                onPressed: _onAdd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
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
