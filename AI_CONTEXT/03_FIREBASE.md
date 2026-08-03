# 03 — Firebase Configuration & Schema

## 1. Firebase Project Overview
- **Firebase Project ID:** `bu-gate2eat`
- **Project Number:** `657799719042`
- **Application ID (Package Name):** `com.bugate2eat.app`
- **Configuration File:** `android/app/google-services.json` (Packaged in APK).

## 2. Firestore Security Rules
Rules published in Firebase Console:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

## 3. Frozen Canonical Firestore Database Schema

### Collection: `shops`
Document IDs: `rajat_shop`, `nayan_shop`

```json
{
  "name": "Rajat Shop",
  "description": "Chinese, Fast Food, Snacks & Special Thalis",
  "bannerUrl": "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=500",
  "contactNumber": "8295643910",
  "orderNumber": "8295643910",
  "openTime": "08:00",
  "closeTime": "23:30",
  "isClosedOverride": false,
  "isActive": true,
  "sortOrder": 1,
  "searchKeywords": ["momos", "chinese", "fast food", "snacks", "thali"],
  "deliveryNote": "Pickup from Gate 2",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

#### Subcollection: `shops/{shopId}/categories`
Document IDs: `momos`, `snacks`, `thalis`
```json
{
  "name": "Momos",
  "sortOrder": 1
}
```

#### Subcollection: `shops/{shopId}/menuItems`
Deterministic Custom Document IDs (`veg_steam_momos`, `hakka_noodles`, etc.):

```json
{
  "name": "Veg Steam Momos",
  "details": "8 Pieces",
  "price": 60,
  "imageUrl": "",
  "categoryId": "momos",
  "isVeg": true,
  "isAvailable": true,
  "isRecommended": true,
  "sortOrder": 1
}
```

## 4. Seeding Guard Logic (`SeedDataService`)
- On startup, `SeedDataService` checks if `rajat_shop` and `nayan_shop` documents exist in Firestore.
- **If both exist**: `SeedDataService` immediately **SKIPS execution** to prevent overwriting prices or menu details edited manually in Firebase Console.
- **If missing**: Seeding creates missing shop documents and custom-ID menu documents according to frozen schema fields.

