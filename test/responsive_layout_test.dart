import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BU Gate2Eat — Responsive Layout & Aspect Ratio Mathematical Suite', () {
    test('Calculate grid aspect ratio across all standard Android screen widths (320px - 430px)', () {
      final widths = [320.0, 360.0, 375.0, 390.0, 412.0, 430.0];

      for (final screenWidth in widths) {
        final horizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 12.0 : 14.0);
        final crossAxisSpacing = screenWidth < 360 ? 8.0 : 10.0;
        final cardWidth = (screenWidth - (horizontalPadding * 2) - crossAxisSpacing) / 2;

        const textScale = 1.0;
        const extraTextHeight = (textScale > 1.0) ? (textScale - 1.0) * 36.0 : 0.0;
        const bodyHeight = 116.0 + extraTextHeight;
        final cardHeight = (cardWidth / 1.3) + bodyHeight;
        final childAspectRatio = cardWidth / cardHeight;

        // Card width must be comfortable
        expect(cardWidth >= 146.0, isTrue);
        // Body height must allocate at least 116px (zero text clipping)
        expect(bodyHeight, equals(116.0));
        // Ratio dynamically adapts from ~0.64 (320px) to ~0.74 (430px)
        expect(childAspectRatio >= 0.63 && childAspectRatio <= 0.76, isTrue);
      }
    });

    test('Calculate grid aspect ratio with Android Accessibility Text Scaling (1.2x)', () {
      const screenWidth = 360.0;
      const horizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 400 ? 12.0 : 14.0);
      const crossAxisSpacing = screenWidth < 360 ? 8.0 : 10.0;
      const cardWidth = (screenWidth - (horizontalPadding * 2) - crossAxisSpacing) / 2;

      const textScale = 1.2;
      const extraTextHeight = (textScale > 1.0) ? (textScale - 1.0) * 36.0 : 0.0;
      const bodyHeight = 116.0 + extraTextHeight;
      const cardHeight = (cardWidth / 1.3) + bodyHeight;
      const childAspectRatio = cardWidth / cardHeight;

      // Body height expands dynamically by 7.2px
      expect(bodyHeight, closeTo(123.2, 0.01));
      // Aspect ratio decreases dynamically to provide vertical space
      expect(childAspectRatio < 0.70, isTrue);
    });
  });
}
