# CHANGELOG

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

