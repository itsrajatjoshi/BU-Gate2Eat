import 'package:bugate2eat_app/features/home/widgets/shop_card.dart';
import 'package:bugate2eat_app/models/shop_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ShopCard 3.7.2: Timing is positioned vertically below Shop Name', (tester) async {
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

    // Verify Shop Name and Timing are present
    final nameFinder = find.text('Raja Hotel');
    final timingFinder = find.text('8:00 AM – 11:30 PM');
    final phoneFinder = find.text('9191919191');

    expect(nameFinder, findsOneWidget);
    expect(timingFinder, findsOneWidget);
    expect(phoneFinder, findsOneWidget);

    // Verify vertical layout: Shop Name Y < Timing Y < Phone Y
    final nameTop = tester.getTopLeft(nameFinder).dy;
    final timingTop = tester.getTopLeft(timingFinder).dy;
    final phoneTop = tester.getTopLeft(phoneFinder).dy;

    expect(nameTop < timingTop, isTrue, reason: 'Timing must be positioned below Shop Name');
    expect(timingTop < phoneTop, isTrue, reason: 'Phone must be positioned below Timing');
  });
}
