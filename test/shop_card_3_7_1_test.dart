import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ShopCard excludes description and pickup note, keeps name, timings, phone', (tester) async {
    final testShop = Shop(
      id: 'shop_1',
      name: 'Raja Hotel',
      description: 'Where cravings get royal treatment. Dive into delicious food.',
      bannerUrl: '',
      contactNumber: '9191919191',
      orderNumber: '9191919191',
      openTime: '08:00',
      closeTime: '23:30',
      isClosedOverride: false,
      isActive: true,
      sortOrder: 1,
      searchKeywords: ['raja', 'hotel'],
      deliveryNote: 'Pickup from Gate 3',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ShopCard(
              shop: testShop,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    // Verify Shop Name is present
    expect(find.text('Raja Hotel'), findsOneWidget);

    // Verify Timing is present
    expect(find.text('8:00 AM – 11:30 PM'), findsOneWidget);

    // Verify Phone number is present
    expect(find.text('9191919191'), findsOneWidget);

    // Verify Description is NOT on the card
    expect(find.text('Where cravings get royal treatment. Dive into delicious food.'), findsNothing);

    // Verify Pickup note is NOT on the card
    expect(find.text('Pickup from Gate 3'), findsNothing);
    expect(find.byIcon(Icons.storefront_outlined), findsNothing);
  });
}
