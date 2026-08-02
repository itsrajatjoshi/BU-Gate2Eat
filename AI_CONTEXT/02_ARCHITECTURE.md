# 02 — Architecture & Technology Stack

## 1. Tech Stack Overview

| Layer | Technology | Version / Package |
|---|---|---|
| **Framework** | Flutter (Dart 3) | Flutter 3.x |
| **State Management** | Riverpod | `flutter_riverpod: ^2.6.1` |
| **Routing** | GoRouter | `go_router: ^14.8.1` |
| **Database** | Cloud Firestore | `cloud_firestore: ^5.6.12` |
| **Local Storage** | SharedPreferences | `shared_preferences: ^2.3.5` |
| **Deep-Linking** | URL Launcher | `url_launcher: ^6.3.1` |
| **Design System** | Google Fonts (Outfit / Inter) | `google_fonts: ^6.2.1` |

## 2. System Architecture & Component Flow

```text
[ User Launch ]
       │
       ▼
[ Splash Screen ] ──(Check Local User Profile)──► [ Onboarding Screen ] (First Launch Only)
       │                                                   │
       ▼ (Profile Exists)                                   ▼ (Save Profile in SharedPreferences)
[ Home Screen ] ◄───────────────────────────────────────────┘
       │
       ├──(Fetch Shops from Firestore via FirestoreService /shops)
       │
       ▼
[ Shop Detail Screen ] ──(Fetch Menu Items & Categories /shops/{shopId}/menuItems)
       │
       ├──(User Adds Items to Riverpod CartNotifier)
       │
       ▼
[ Cart Screen ]
       │
       └──(Tap "Place Order via WhatsApp")
               │
               ▼
[ WhatsApp Service ] ──(Construct Formatted Text & Deep-Link)──► [ WhatsApp App (+91 Vendor Phone) ]
```

## 3. Directory Structure Map

```text
lib/
├── main.dart                      # App entry point, Firebase init & SeedDataService call
├── app_constants.dart             # Colors, typography, spacing, app constants
├── core/
│   ├── router.dart                # GoRouter route configurations
│   ├── providers.dart             # Global Riverpod providers
│   └── theme/
│       └── app_theme.dart         # Dark/Light Material 3 AppTheme
├── models/
│   ├── shop_model.dart            # Shop data model & Firestore factory
│   ├── category_model.dart        # Category model & Firestore factory
│   ├── menu_item_model.dart       # Menu item model & Firestore factory
│   └── user_profile_model.dart    # User profile model (Name, Phone, Age)
├── services/
│   ├── firestore_service.dart     # Firestore read operations & offline fallback data
│   ├── local_storage_service.dart # SharedPreferences wrapper for profile & theme
│   ├── seed_data_service.dart      # Idempotent Firestore database seeder
│   └── whatsapp_service.dart      # WhatsApp URL launcher & text formatting
└── features/
    ├── splash/                    # Splash screen with auto-navigation
    ├── onboarding/                # User profile form (Name, Phone validation)
    ├── home/                      # Shop list view, search, & status badges
    ├── shop/                      # Menu category tabs, item steppers, Veg filter
    ├── cart/                      # Cart items list, total calculation, WhatsApp trigger
    └── settings/                  # Profile view/edit & Theme selector
```
