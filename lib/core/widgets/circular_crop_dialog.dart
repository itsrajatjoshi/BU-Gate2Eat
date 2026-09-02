// BU Gate2Eat — Core UI Widgets
// Circular Crop Dialog & Image Crop Helper (Square output for circular shop photo)
// Single Source of Truth: CanonicalCropState in original image pixel coordinates

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../constants/app_constants.dart';

/// Canonical crop state maintaining the single source of truth in source-image pixel coordinates.
/// Both visual preview and final 512x512 export derive directly from this state.
class CanonicalCropState {
  CanonicalCropState({
    required this.sourceWidth,
    required this.sourceHeight,
    Offset? center,
    double zoom = 1.0,
  })  : _zoom = zoom.clamp(1.0, 4.0),
        _center = center ??
            Offset(sourceWidth / 2.0, sourceHeight / 2.0) {
    _clampCenter();
  }

  final int sourceWidth;
  final int sourceHeight;

  Offset _center;
  double _zoom;

  Offset get center => _center;
  double get zoom => _zoom;

  /// Maximum possible square side length that fits in the source image.
  double get maxSquareSide => math.min(sourceWidth, sourceHeight).toDouble();

  /// Current square crop side length in source pixels.
  double get cropSize => maxSquareSide / _zoom;

  /// Canonical square crop rectangle in original source pixel coordinates.
  Rect get cropRect {
    final double half = cropSize / 2.0;
    return Rect.fromLTWH(
      _center.dx - half,
      _center.dy - half,
      cropSize,
      cropSize,
    );
  }

  /// Clamps the crop center so the square cropRect is always 100% within [0, 0, sourceWidth, sourceHeight].
  void _clampCenter() {
    final double half = cropSize / 2.0;
    final double minX = half;
    final double maxX = math.max(half, sourceWidth - half);
    final double minY = half;
    final double maxY = math.max(half, sourceHeight - half);

    _center = Offset(
      _center.dx.clamp(minX, maxX),
      _center.dy.clamp(minY, maxY),
    );
  }

  /// Pan by a screen delta in points (from user drag gesture).
  ///
  /// [deltaScreen] is the movement in screen pixels.
  /// [guideDiameter] is the physical diameter of the circular crop guide (e.g. 240.0).
  ///
  /// Dragging image to the right (deltaScreen.dx > 0) moves crop window left (deltaSource.dx < 0).
  void panBy(Offset deltaScreen, double guideDiameter) {
    if (guideDiameter <= 0) return;
    final double screenToSourceFactor = cropSize / guideDiameter;
    _center = Offset(
      _center.dx - deltaScreen.dx * screenToSourceFactor,
      _center.dy - deltaScreen.dy * screenToSourceFactor,
    );
    _clampCenter();
  }

  /// Sets zoom level in range [1.0, 4.0] while preserving center focus and clamping to image bounds.
  void setZoom(double newZoom) {
    _zoom = newZoom.clamp(1.0, 4.0);
    _clampCenter();
  }

  /// Scales current zoom by factor (from pinch gesture).
  void scaleZoom(double factor) {
    setZoom(_zoom * factor);
  }

  /// Resets crop state to centered default at zoom 1.0.
  void reset() {
    _zoom = 1.0;
    _center = Offset(sourceWidth / 2.0, sourceHeight / 2.0);
    _clampCenter();
  }
}

/// Pure image cropping utilities.
class ImageCropHelper {
  /// Directly crops the canonical square region in source-image pixels and resizes to targetDimension (e.g. 512x512).
  static Uint8List cropCanonical({
    required Uint8List rawBytes,
    required Rect canonicalCropRect,
    int targetDimension = 512,
  }) {
    img.Image? decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    // Bake EXIF orientation so pixel buffer is upright and matches visual display
    decoded = img.bakeOrientation(decoded);

    final int imgW = decoded.width;
    final int imgH = decoded.height;

    int cropX = canonicalCropRect.left.round().clamp(0, imgW - 1);
    int cropY = canonicalCropRect.top.round().clamp(0, imgH - 1);
    int cropSide = canonicalCropRect.width.round();

    cropSide = cropSide.clamp(1, math.min(imgW - cropX, imgH - cropY));

    final img.Image cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropSide,
      height: cropSide,
    );

    final img.Image resized = img.copyResize(
      cropped,
      width: targetDimension,
      height: targetDimension,
      interpolation: img.Interpolation.linear,
    );

    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  /// Crops a square region from the source image bytes and scales to targetDimension (e.g. 512x512).
  ///
  /// Normalized parameters (0.0 to 1.0) define the relative position of the crop square
  /// inside the original image coordinate space.
  static Uint8List cropSquare({
    required Uint8List rawBytes,
    double normalizedX = 0.0,
    double normalizedY = 0.0,
    double normalizedSize = 1.0,
    int targetDimension = 512,
  }) {
    img.Image? decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    // Bake EXIF orientation so pixel buffer is upright
    decoded = img.bakeOrientation(decoded);

    final int imgW = decoded.width;
    final int imgH = decoded.height;

    // If default parameters, produce centered square crop
    if (normalizedX == 0.0 && normalizedY == 0.0 && normalizedSize == 1.0) {
      final int side = math.min(imgW, imgH);
      final int cropX = (imgW - side) ~/ 2;
      final int cropY = (imgH - side) ~/ 2;

      final img.Image cropped = img.copyCrop(
        decoded,
        x: cropX,
        y: cropY,
        width: side,
        height: side,
      );

      final img.Image resized = img.copyResize(
        cropped,
        width: targetDimension,
        height: targetDimension,
        interpolation: img.Interpolation.linear,
      );

      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    }

    int cropX = (normalizedX * imgW).round().clamp(0, imgW - 1);
    int cropY = (normalizedY * imgH).round().clamp(0, imgH - 1);
    int cropSize = (normalizedSize * math.min(imgW, imgH)).round();
    cropSize = cropSize.clamp(1, math.min(imgW - cropX, imgH - cropY));

    final img.Image cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropSize,
      height: cropSize,
    );

    final img.Image resized = img.copyResize(
      cropped,
      width: targetDimension,
      height: targetDimension,
      interpolation: img.Interpolation.linear,
    );

    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  /// Calculates the crop square parameters from viewport transformation and image dimensions.
  static Uint8List cropFromViewportTransform({
    required Uint8List rawBytes,
    required Matrix4 transformMatrix,
    required Size viewportSize,
    required double circleDiameter,
    required Size childImageSize,
    int targetDimension = 512,
  }) {
    img.Image? decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    // Bake EXIF orientation so pixel buffer is upright and matches visual display
    decoded = img.bakeOrientation(decoded);

    final double imgW = decoded.width.toDouble();
    final double imgH = decoded.height.toDouble();

    // The circle cutout is centered in viewport
    final Offset circleCenterVp =
        Offset(viewportSize.width / 2, viewportSize.height / 2);
    final double circleRadius = circleDiameter / 2;

    // Viewport coordinates of the crop bounding box
    final Offset vpTopLeft =
        circleCenterVp - Offset(circleRadius, circleRadius);
    final Offset vpBottomRight =
        circleCenterVp + Offset(circleRadius, circleRadius);

    // Inverse transform from viewport coordinates to child coordinates
    final Matrix4 inverse = Matrix4.zero();
    final double det = inverse.copyInverse(transformMatrix);
    if (det == 0.0) {
      // Degenerate transform: fallback to centered square
      return cropSquare(
        rawBytes: rawBytes,
        targetDimension: targetDimension,
      );
    }

    final Offset childTopLeft =
        MatrixUtils.transformPoint(inverse, vpTopLeft);
    final Offset childBottomRight =
        MatrixUtils.transformPoint(inverse, vpBottomRight);

    // Map child coordinates (relative to rendered image widget) to actual original image pixels
    final double scaleX = imgW / childImageSize.width;
    final double scaleY = imgH / childImageSize.height;

    final double pixelX1 = childTopLeft.dx * scaleX;
    final double pixelY1 = childTopLeft.dy * scaleY;
    final double pixelX2 = childBottomRight.dx * scaleX;
    final double pixelY2 = childBottomRight.dy * scaleY;

    // Determine square crop bounds
    final double minX = math.min(pixelX1, pixelX2);
    final double minY = math.min(pixelY1, pixelY2);
    final double maxX = math.max(pixelX1, pixelX2);
    final double maxY = math.max(pixelY1, pixelY2);

    final double boxW = maxX - minX;
    final double boxH = maxY - minY;
    final double squareSide = math.min(boxW, boxH);

    final Rect rect = Rect.fromLTWH(minX, minY, squareSide, squareSide);
    return cropCanonical(
      rawBytes: rawBytes,
      canonicalCropRect: rect,
      targetDimension: targetDimension,
    );
  }
}

/// Data class representing normalized image dimensions and orientation-baked bytes.
class _NormalizedImageData {
  const _NormalizedImageData({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Normalize image and bake EXIF orientation.
_NormalizedImageData _normalizeAndBake(Uint8List rawBytes) {
  img.Image? decoded = img.decodeImage(rawBytes);
  if (decoded == null) {
    return _NormalizedImageData(
      bytes: rawBytes,
      width: 512,
      height: 512,
    );
  }

  // Bake EXIF orientation so pixel buffer is upright and matches visual display
  decoded = img.bakeOrientation(decoded);

  final Uint8List normalized = Uint8List.fromList(
    img.encodeJpg(decoded, quality: 92),
  );

  return _NormalizedImageData(
    bytes: normalized,
    width: decoded.width,
    height: decoded.height,
  );
}

/// Interactive modal for selecting circular shop photo portion.
class CircularCropDialog extends StatefulWidget {
  const CircularCropDialog({
    required this.imageBytes,
    this.title = 'Adjust Shop Photo',
    super.key,
  });

  final Uint8List imageBytes;
  final String title;

  /// Shows the dialog and returns cropped square image bytes, or null if cancelled.
  static Future<Uint8List?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    String title = 'Adjust Shop Photo',
  }) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CircularCropDialog(
        imageBytes: imageBytes,
        title: title,
      ),
    );
  }

  @override
  State<CircularCropDialog> createState() => _CircularCropDialogState();
}

class _CircularCropDialogState extends State<CircularCropDialog> {
  bool _isInitializing = true;
  bool _isProcessing = false;

  Uint8List? _normalizedBytes;
  ui.Image? _uiImage;
  late CanonicalCropState _cropState;

  double _initialZoom = 1.0;

  static const double _circleDiameter = 240.0;
  static const double _viewportSize = 280.0;

  @override
  void initState() {
    super.initState();
    try {
      final _NormalizedImageData data = _normalizeAndBake(widget.imageBytes);
      _normalizedBytes = data.bytes;
      _cropState = CanonicalCropState(
        sourceWidth: data.width,
        sourceHeight: data.height,
      );
    } catch (e) {
      debugPrint('⚠️ Image normalization error: $e');
      _cropState = CanonicalCropState(
        sourceWidth: 512,
        sourceHeight: 512,
      );
    }
    _loadUiImage();
  }

  Future<void> _loadUiImage() async {
    try {
      if (_normalizedBytes != null) {
        final ui.Codec codec =
            await ui.instantiateImageCodec(_normalizedBytes!);
        final ui.FrameInfo frame = await codec.getNextFrame();

        if (mounted) {
          setState(() {
            _uiImage = frame.image;
            _isInitializing = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isInitializing = false;
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ Image ui decode error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  void _resetTransform() {
    setState(() {
      _cropState.reset();
    });
  }

  void _zoomTo(double targetZoom) {
    setState(() {
      _cropState.setZoom(targetZoom);
    });
  }

  Future<void> _confirmCrop() async {
    setState(() => _isProcessing = true);

    try {
      final Uint8List sourceBytes = _normalizedBytes ?? widget.imageBytes;
      final Rect canonicalRect = _cropState.cropRect;

      debugPrint('=== [CANONICAL CROP EXPORT] ===');
      debugPrint(
          '📸 Source dimensions: ${_cropState.sourceWidth}x${_cropState.sourceHeight}');
      debugPrint('🔍 Current zoom: ${_cropState.zoom.toStringAsFixed(3)}');
      debugPrint(
          '📍 Current center: (${_cropState.center.dx.toStringAsFixed(1)}, ${_cropState.center.dy.toStringAsFixed(1)})');
      debugPrint(
          '✂️ Canonical cropRect: [${canonicalRect.left.toStringAsFixed(1)}, ${canonicalRect.top.toStringAsFixed(1)}, ${canonicalRect.width.toStringAsFixed(1)} x ${canonicalRect.height.toStringAsFixed(1)}]');
      debugPrint('🎯 Target output: 512x512 square');
      debugPrint('================================');

      // Direct canonical crop using the exact source-pixel rectangle
      final Uint8List croppedBytes = ImageCropHelper.cropCanonical(
        rawBytes: sourceBytes,
        canonicalCropRect: canonicalRect,
        targetDimension: 512,
      );

      if (mounted) {
        Navigator.of(context).pop(croppedBytes);
      }
    } catch (e) {
      debugPrint('❌ Crop processing error: $e');
      // Fallback: simple center crop
      try {
        final Uint8List fallback = ImageCropHelper.cropSquare(
          rawBytes: _normalizedBytes ?? widget.imageBytes,
          targetDimension: 512,
        );
        if (mounted) {
          Navigator.of(context).pop(fallback);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to crop photo.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.crop_free_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _isProcessing
                      ? null
                      : () => Navigator.of(context).pop(null),
                  tooltip: 'Cancel',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Drag image to reposition • Pinch or use slider to zoom',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),

            // Canonical Viewport with Direct Source-Rect CustomPainter
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: _viewportSize,
                height: _viewportSize,
                color: Colors.black,
                child: GestureDetector(
                  onScaleStart: (details) {
                    _initialZoom = _cropState.zoom;
                  },
                  onScaleUpdate: (details) {
                    if (details.scale == 1.0) {
                      // Pan gesture
                      final Offset delta = details.focalPointDelta;
                      if (delta != Offset.zero) {
                        setState(() {
                          _cropState.panBy(delta, _circleDiameter);
                        });
                      }
                    } else {
                      // Pinch-to-zoom + Pan gesture
                      setState(() {
                        _cropState.setZoom(_initialZoom * details.scale);
                        final Offset delta = details.focalPointDelta;
                        if (delta != Offset.zero) {
                          _cropState.panBy(delta, _circleDiameter);
                        }
                      });
                    }
                  },
                  child: CustomPaint(
                    size: const Size(_viewportSize, _viewportSize),
                    painter: _CropCanvasPainter(
                      image: _uiImage,
                      cropState: _cropState,
                      guideDiameter: _circleDiameter,
                      isDark: isDark,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Zoom Slider & Reset Controls
            Row(
              children: [
                const Icon(Icons.zoom_out_rounded,
                    size: 18, color: Colors.grey),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primary,
                      thumbColor: AppColors.primary,
                      overlayColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _cropState.zoom.clamp(1.0, 3.5),
                      min: 1.0,
                      max: 3.5,
                      onChanged: _isProcessing
                          ? null
                          : (val) {
                              _zoomTo(val);
                            },
                    ),
                  ),
                ),
                const Icon(Icons.zoom_in_rounded,
                    size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: _isProcessing ? null : _resetTransform,
                  tooltip: 'Reset position',
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _confirmCrop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Save Photo',
                            style: TextStyle(fontWeight: FontWeight.bold),
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

/// Custom painter that paints the source image and circular stencil overlay.
///
/// Guaranteed Invariant: The region inside the circular crop guide (bounding box [guideBox])
/// maps 100% directly and identically to [cropState.cropRect] in source image pixels.
class _CropCanvasPainter extends CustomPainter {
  _CropCanvasPainter({
    required this.image,
    required this.cropState,
    required this.guideDiameter,
    required this.isDark,
  });

  final ui.Image? image;
  final CanonicalCropState cropState;
  final double guideDiameter;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final double guideLeft = (size.width - guideDiameter) / 2.0;
    final double guideTop = (size.height - guideDiameter) / 2.0;
    final Offset circleCenter = Offset(size.width / 2.0, size.height / 2.0);
    final double circleRadius = guideDiameter / 2.0;

    // 1. Draw source image mapped identically to canonical cropRect
    if (image != null) {
      final Rect cropRect = cropState.cropRect;
      final double scale = guideDiameter / cropState.cropSize;

      // Position full image such that cropRect is located precisely inside guideBox [guideLeft, guideTop, guideDiameter, guideDiameter]
      final double destLeft = guideLeft - cropRect.left * scale;
      final double destTop = guideTop - cropRect.top * scale;
      final double destWidth = cropState.sourceWidth * scale;
      final double destHeight = cropState.sourceHeight * scale;

      final Rect srcFullRect = Rect.fromLTWH(
        0,
        0,
        cropState.sourceWidth.toDouble(),
        cropState.sourceHeight.toDouble(),
      );
      final Rect destFullRect = Rect.fromLTWH(
        destLeft,
        destTop,
        destWidth,
        destHeight,
      );

      canvas.drawImageRect(
        image!,
        srcFullRect,
        destFullRect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    // 2. Dark stencil overlay with circular hole
    final Path overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: circleCenter, radius: circleRadius))
      ..fillType = PathFillType.evenOdd;

    final Paint overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlayPath, overlayPaint);

    // 3. Crisp circular guide ring
    final Paint borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(circleCenter, circleRadius, borderPaint);

    // 4. Subtle inner rule-of-thirds grid
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Horizontal grid lines
    canvas.drawLine(
      Offset(circleCenter.dx - circleRadius * 0.7,
          circleCenter.dy - circleRadius / 3.0),
      Offset(circleCenter.dx + circleRadius * 0.7,
          circleCenter.dy - circleRadius / 3.0),
      gridPaint,
    );
    canvas.drawLine(
      Offset(circleCenter.dx - circleRadius * 0.7,
          circleCenter.dy + circleRadius / 3.0),
      Offset(circleCenter.dx + circleRadius * 0.7,
          circleCenter.dy + circleRadius / 3.0),
      gridPaint,
    );

    // Vertical grid lines
    canvas.drawLine(
      Offset(circleCenter.dx - circleRadius / 3.0,
          circleCenter.dy - circleRadius * 0.7),
      Offset(circleCenter.dx - circleRadius / 3.0,
          circleCenter.dy + circleRadius * 0.7),
      gridPaint,
    );
    canvas.drawLine(
      Offset(circleCenter.dx + circleRadius / 3.0,
          circleCenter.dy - circleRadius * 0.7),
      Offset(circleCenter.dx + circleRadius / 3.0,
          circleCenter.dy + circleRadius * 0.7),
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropCanvasPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.cropState.cropRect != cropState.cropRect ||
        oldDelegate.guideDiameter != guideDiameter ||
        oldDelegate.isDark != isDark;
  }
}
