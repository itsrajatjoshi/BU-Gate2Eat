# 01 — Current Status

## Project Status Snapshot (As of August 3, 2026)

| Parameter | Current Status |
|---|---|
| **App Version** | `1.0.1+2` |
| **Current Branch** | `main` |
| **Latest Commit** | `c4038fd` (`origin/main`) |
| **Build Status** | ✅ Release APK Working (`BU_Gate2Eat_v1.apk`) |
| **UI Design System** | ✅ Google Stitch MCP Integrated & Active (Project `6396413867463778857`) |
| **Active Shop Card** | ✅ Exact Pixel Replica of Reference Screenshots (Light & Dark modes, 2-line Glass Open Badge `🟢 OPEN / Till 11:30 PM`, Rounded Contact & Pickup Footer Chips, Borderless Search Input) |
| **Local Web Server** | ✅ Live on `http://localhost:8080` |
| **Firestore Database** | ✅ Frozen Schema Active & 100% Single Source of Truth (`bu-gate2eat`) |
| **Static Code Health** | ✅ `flutter analyze` — 0 Errors, 0 Warnings |
| **Known Blocking Issues** | **None** |

## Active Environment & Artifacts
- **APK Location (Downloads):** `C:\Users\rajat\Downloads\BU_Gate2Eat_v1.apk` (18.6 MB)
- **APK Location (Project Build):** `d:\app\BUGate2Eat App v1\build\app\outputs\flutter-apk\app-release.apk`
- **Active Device Testing:** Tested and verified live on `motorola edge 60 fusion` (Android 16).

## Active Data Summary
- **Single Source of Truth:** 100% loaded dynamically from Cloud Firestore with native disk persistence cache (`Settings(persistenceEnabled: true)`).
- **Shops Active:** 2 Shops (**Rajat Shop** & **Nayan Shop**).
- **Rajat Shop Order Contact:** `8295643910` (11 menu items).
- **Nayan Shop Order Contact:** `8875344034` (12 menu items).

- **Firestore Seeding:** Uses deterministic custom document IDs (`veg_steam_momos`, `hakka_noodles`, etc.) matching frozen schema.

## Next Tasks / Milestones
- **Current Milestone:** Production Rollout & Gate 2 Student Testing.
- **Future Milestone:** Vendor Admin Panel (Web/Mobile Dashboard for Firestore CRUD).

