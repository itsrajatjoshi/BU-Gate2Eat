# 01 — Current Status

## Project Status Snapshot (As of August 12, 2026)

| Parameter | Current Status |
|---|---|
| **App Version** | `1.0.7` |
| **Flutter SDK** | ✅ Upgraded to `3.44.9` (Stable Channel) |
| **Current Branch** | `main` |
| **Latest Commit** | Shop-Scoped Favourites Fix + Tests |
| **Bottom Navigation** | ✅ 4-Tab Main Navigation: `Home` → `Favourites` → `Cart` → `Profile` |
| **Favourites Screen** | ✅ Live Favourites list with shop-scoped identity (`shopId:itemId`), attribution, veg/non-veg indicator, price, remove action, add to cart & clean empty state |
| **Cart Persistence** | ✅ Cart lifetime uncoupled from ShopDetailScreen; persists across tabs; cross-shop conflict protection preserved |
| **Home Filters** | ✅ Horizontal Filter Pills (`All`, `Open Now`, `Fast Food`, `Snacks`, `Thalis`, `Chinese`, `Veg`, `Non-Veg`) |
| **Profile & Settings Separation** | ✅ Profile dedicated to User details (Name, Phone, Age, Pickup Info); Settings dedicated to Appearance & About |
| **Category Navigation UI** | ✅ Pinned Sticky & 100% Connected to Cloud Firestore (`shops/{shopId}/categories`) |
| **Scroll-Spy Sync** | ✅ Domino's / Swiggy Style Auto Scroll & Active Section Highlighting |
| **Build Status** | ✅ Web Release Built & Verified (`build/web`) |
| **Static Code Health** | ✅ `flutter analyze` — 0 Errors, 0 Warnings |
| **Test Suite Health** | ✅ `flutter test` — 34/34 Tests Passed |
| **Known Blocking Issues** | **None** |

## Active Environment & Artifacts
- **APK Location (Downloads):** `C:\Users\rajat\Downloads\BU_Gate2Eat_v1.apk` (18.4 MB — ARM64 Release Build)
- **APK Location (Project Build):** `d:\app\BUGate2Eat App v1\build\app\outputs\flutter-apk\app-release.apk`
- **Web App Location:** `http://127.0.0.1:8080` (served in release mode via `build/web`)
- **Active Device Testing:** Tested and verified live on `motorola edge 60 fusion` (Android 16) and Web browser.

## Data Summary
- **Single Source of Truth:** 100% loaded dynamically from Cloud Firestore with native disk persistence cache (`Settings(persistenceEnabled: true)`).
- **Shops Active:** 2 Shops (**Rajat Shop** & **Nayan Shop**).
- **Rajat Shop Order Contact:** `8295643910` (11 menu items).
- **Nayan Shop Order Contact:** `8875344034` (12 menu items).
- **Firestore Seeding:** Uses deterministic custom document IDs (`veg_steam_momos`, `hakka_noodles`, etc.) matching frozen schema.

## Next Tasks / Milestones
- **Current Milestone:** Production Rollout & Gate 2 Student Testing.
- **Future Milestone:** Vendor Admin Panel (Web/Mobile Dashboard for Firestore CRUD).
