# 01 — Current Status

## Project Status Snapshot (As of August 3, 2026)

| Parameter | Current Status |
|---|---|
| **App Version** | `1.0.1+2` |
| **Flutter SDK** | ✅ Upgraded to `3.44.9` (Stable Channel) |
| **Current Branch** | `main` |
| **Latest Commit** | `52b2569` (`origin/main`) |
| **Build Status** | ✅ Release APK Working (`BU_Gate2Eat_v1.apk`) |
| **UI Design System** | ✅ Google Stitch MCP Integrated & Active (Project `6396413867463778857`) |
| **Active Shop Card** | ✅ Locked & Final (Variant 3 Modern Split Row) |
| **Local Web Server** | ✅ Running Live on `http://127.0.0.1:8080` |
| **Firestore Database** | ✅ Frozen Schema Active & 100% Single Source of Truth (`bu-gate2eat`) |
| **Static Code Health** | ✅ `flutter analyze` — 0 Errors, 0 Warnings |
| **Known Blocking Issues** | **None** |

## Active Environment & Artifacts
- **APK Location (Downloads):** `C:\Users\rajat\Downloads\BU_Gate2Eat_v1.apk` (18.4 MB — ARM64 Release Build)
- **APK Location (Project Build):** `d:\app\BUGate2Eat App v1\build\app\outputs\flutter-apk\app-release.apk`
- **Web App Location:** `http://127.0.0.1:8080` (served in release mode via `flutter run -d web-server --release`)
- **Active Device Testing:** Tested and verified live on `motorola edge 60 fusion` (Android 16) and Web browser. Data Summary
- **Single Source of Truth:** 100% loaded dynamically from Cloud Firestore with native disk persistence cache (`Settings(persistenceEnabled: true)`).
- **Shops Active:** 2 Shops (**Rajat Shop** & **Nayan Shop**).
- **Rajat Shop Order Contact:** `8295643910` (11 menu items).
- **Nayan Shop Order Contact:** `8875344034` (12 menu items).

- **Firestore Seeding:** Uses deterministic custom document IDs (`veg_steam_momos`, `hakka_noodles`, etc.) matching frozen schema.

## Next Tasks / Milestones
- **Current Milestone:** Production Rollout & Gate 2 Student Testing.
- **Future Milestone:** Vendor Admin Panel (Web/Mobile Dashboard for Firestore CRUD).

