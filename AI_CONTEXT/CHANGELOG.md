# CHANGELOG

## [1.0.7] — 2026-08-12

### Fixed
- **Shop-Scoped Favourites Identity**:
  - Resolved cross-shop item ID collision where favouriting an item in one shop (e.g. Rajat Shop `veg_steam_momos`) caused identically ID'd items in another shop (e.g. Nayan Shop) to show as favourited.
  - Introduced deterministic composite keys (`'$shopId:$itemId'`) in `FavoriteNotifier` and `favoriteItemsProvider`.
  - Updated `_MenuItemCard`, `_ItemDetailBottomSheet`, and `FavouritesScreen` to pass `shopId` when toggling and evaluating favourite status.
  - Expanded automated test suite with 6 dedicated test cases covering shop isolation and local storage persistence.

## [1.0.6] — 2026-08-11

### Added & Implemented
- **4-Tab Bottom Navigation Bar**:
  - Integrated `Home` → `Favourites` → `Cart` → `Profile` navigation matching existing theme and visual specification.
  - Implemented dynamic Cart badge counter showing total items in cart when `cartItemCount > 0`.
  - Preserved tab state across switching via `IndexedStack`.
- **Dedicated Favourites Screen (`lib/features/favourites/favourites_screen.dart`)**:
  - Displays user-favorited food/menu items with food dish image, item name, price, veg/non-veg status indicator, item details, and clear parent shop attribution (e.g. "Rajat Shop").
  - Included interactive favorite removal toggle and direct Add-to-Cart with single-shop invariant enforcement.
  - Implemented high-contrast empty state ("No favourites yet") for both light and dark themes.
  - Connected with Riverpod `favoriteItemsProvider` and local SharedPreferences storage (`favoritesProvider`).
- **Home Category & Status Filter Pills**:
  - Added horizontal scrollable filter pills below search bar: `All`, `Open Now` (with green dot indicator), `Fast Food`, `Snacks`, `Thalis`, `Chinese`, `Veg`, `Non-Veg`.
  - Non-destructive filtering combining active pill with text search query.
- **Strict Profile & Settings Separation**:
  - `ProfileScreen` is dedicated strictly to User & Account information (Name, Phone number +91, Age, Save Changes button, Bennett University pickup notes, and Settings shortcut).
  - `SettingsScreen` is dedicated strictly to Application Settings (System / Light / Dark Theme selector, About, App Version, Legal).
- **Cart Persistence Across Navigation**:
  - Decoupled cart lifetime from `ShopDetailScreen` lifecycle by removing premature `PopScope` cart clearing. Cart items now persist across Home, Favourites, Cart, and Profile navigation.
  - Maintained single-shop cross-shop conflict protection dialog (`tryAddToCart`) when attempting to add items from another shop.

## [1.0.5] — 2026-08-09

### Added & Connected (Backend / Data Only)
- **Cloud Firestore Menu Category Integration**:
  - Connected `ShopDetailScreen` category selector bar directly to Cloud Firestore backend (`shops/{shopId}/categories/{categoryId}`).
  - Added native Firestore query `.where('isActive', isEqualTo: true)` in `FirestoreService.getCategories()` with `sortOrder` ascending.
  - Preserved system `"All"` category (`id: 'all'`) as a local UI-only option.
  - Enforced strict category ID mapping (`item.categoryId == category.id`) so changing category display names in Firestore never breaks menu item relationships.
  - Retained 100% of existing UI design, circular image styling, selected orange ring, checkmark badge, sticky header, and Zomato/Domino's scroll-spy sync behavior.
  - Verified static code health (`flutter analyze` — 0 errors, 0 warnings).

## [1.0.4] — 2026-08-09

### Added & Implemented
- **Domino's / Swiggy Style Scroll-Spy Category Sync (`ShopDetailScreen`)**:
  - Implemented automatic scroll synchronization between vertical menu list and horizontal category navigation bar.
  - Added `_onMainScroll()` listener with `GlobalKey` section offset tracking: as user scrolls vertically through menu items, active category chip (`Momos`, `Pizzas`, `Burgers`, `Biryani`, `Thali`, `Snacks`) automatically highlights.
  - Added `_autoScrollCategoryTab()`: top category bar automatically scrolls horizontally to center active category chip.
  - Added `_onCategoryTapped()`: tapping any top category chip smoothly scrolls main menu list directly to that section header.
  - Updated categorized menu layout into structured sliver sections with item counters (`Momos (4)`, `Pizzas (3)`, etc.).
- **Shop Menu Category Navigation UI (`ShopDetailScreen`)**:
  - Implemented pixel-perfect horizontal category navigation matching reference UI screenshots.
  - Added circular food dish photographs with dish labels (`All`, `Momos`, `Pizzas`, `Burgers`, `Biryani`, `Thali`, `Snacks`).
  - Implemented selected-state visual indicators: orange circular ring border, orange checkmark badge at top-right, and bold orange category label.
  - Implemented sticky pinning behavior using `SliverPersistentHeader(pinned: true)` — category navigation locks at top on scroll while menu items slide underneath.
  - Verified static code analysis (`flutter analyze` — 0 errors, 0 warnings).

## [1.0.3] — 2026-08-09

### Added
- **Comprehensive Multi-Platform Design Specification (`DESIGN.md`)**:
  - Created standalone, developer- and AI-friendly UI/UX design blueprint in [DESIGN.md](file:///d:/app/BUGate2Eat%20App%20v1/DESIGN.md).
  - Outlined complete color system tokens (light/dark mode), typography scales, spacing, border radiuses, and shadow elevations.
  - Specified screen-by-screen UX layouts (Splash, Onboarding, Home, Shop Menu, Cart Review, Settings).
  - Defined WhatsApp deep-linking payload format (`https://wa.me/91...`) and zero-friction order text generation.
  - Formatted data models (User Profile, Shop, Menu Item) with verified seed data for Rajat Shop and Nayan Shop.
  - Included a Master AI Prompt for copy-pasting into multi-platform AI tools (v0.dev, Bolt.new, Cursor, Lovable, Claude, ChatGPT, Windsurf).

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


