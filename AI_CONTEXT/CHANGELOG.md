# CHANGELOG

## [1.0.2] — 2026-08-07

### Upgraded
- **Flutter SDK Upgrade**: Upgraded Flutter framework from `3.44.8` to `3.44.9` (Stable Channel).
- **Shop Card UI**: Design frozen as final per user sign-off (`06_DECISIONS.md`).

## [1.0.1] — 2026-08-03

### Changed & Refactored
- **Google Stitch Design System & Shop Card Variant 3**:
  - Integrated Google Stitch MCP (`StitchMCP`) and established BU Gate2Eat Design System.
  - Implemented modular `ShopCard` widget (`lib/features/home/widgets/shop_card.dart`) based on **Variant 3 (Modern Split Row)**:
    - 16:9 banner image with top-left floating glassmorphic **OPEN** / **CLOSED** status pill.
    - Title header row displaying shop name & operational hours (`08:00 AM - 11:30 PM`).
    - One-line shop description.
    - Light slate footer container (`#F8FAFC`) grouping non-clickable contact text (`Contact: 8295643910`) and pickup note (`Pickup from Gate 2`).
    - Zero ratings, zero reviews, zero distance, zero ETA, zero fees, zero call/whatsapp buttons.
- **Frozen Canonical Firestore Database Schema**:
  - `shops`: `name`, `description`, `bannerUrl`, `contactNumber`, `orderNumber`, `openTime`, `closeTime`, `isClosedOverride`, `isActive`, `sortOrder`, `searchKeywords`, `deliveryNote`, `createdAt`, `updatedAt`.
  - `categories`: `name`, `sortOrder`.
  - `menuItems`: `name`, `details`, `price` (as integer), `imageUrl`, `categoryId`, `isVeg`, `isAvailable`, `isRecommended`, `sortOrder`.
- **100% Dynamic Data Architecture**: Removed all hardcoded fallback mock arrays from `FirestoreService`.
- **Offline Persistence & Riverpod Caching**: Enabled `FirebaseFirestore.instance.settings = Settings(persistenceEnabled: true)` and created cached Riverpod providers (`shopsProvider`, `shopCategoriesProvider`, `shopMenuItemsProvider`, `recommendedMenuItemsProvider`).
- **UI & Shop Detail Refinement**:
  - Added **"You may also like"** recommendation section in Cart Screen for same-shop items (`isRecommended == true`).

## [1.0.0] — 2026-08-01

### Added
- Renamed application to **BU Gate2Eat** (`com.bugate2eat.app`).
- Firebase Cloud Firestore integration (`bu-gate2eat`).
- Real vendor shop data for **Rajat Shop** (`+91 8295643910`) and **Nayan Shop** (`+91 8875344034`).
- Custom deterministic Firestore document IDs (`veg_steam_momos`, `hakka_noodles`, etc.).
- Internet permissions `<uses-permission android:name="android.permission.INTERNET"/>` and `ACCESS_NETWORK_STATE` in `android/app/src/main/AndroidManifest.xml`.
- On-screen error message display and console stacktrace logging in `home_screen.dart`.
- Permanent AI Memory System in `AI_CONTEXT/` and `AI_START_HERE.md`.

### Fixed
- Fixed Kotlin package path in `MainActivity.kt` (`com.bugate2eat.app`).
- Fixed cross-drive Windows compilation issue by adding `kotlin.incremental=false` to `gradle.properties`.
- Fixed splash screen freeze by making database seeding non-blocking with 1-second timeout.
- Fixed Firestore `PERMISSION_DENIED` issue by updating Firestore Security Rules to `allow read, write: if true;`.
- Fixed manual price overwrite bug by adding guard `if (rajatDoc.exists && nayanDoc.exists) return;` in `SeedDataService`.

### Build
- Generated fresh standalone release APK: `C:\Users\rajat\Downloads\BU_Gate2Eat_v1.apk` (50.9 MB).
- Tested live on Motorola Edge 60 Fusion.


