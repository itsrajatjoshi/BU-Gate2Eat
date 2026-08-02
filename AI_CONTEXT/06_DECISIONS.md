# 06 — Architectural & Design Decisions

## Key Project Decisions (Immutable Rules for AI)

1. **No User Authentication / Login Required**:
   - Students do NOT sign up or log in.
   - User profile (Name, 10-digit Indian Mobile Phone, Age 15-30) is collected once on first launch and stored locally using `SharedPreferences`.

2. **No In-App Payment Gateway**:
   - Payments are handled offline at pickup (Cash / UPI at Bennett Gate No. 2).
   - Keeps app 100% free, avoids payment gateway commission fees, and eliminates payment failure support overhead.

3. **WhatsApp Deep-Linking as Core Order Flow**:
   - Vendor receive orders directly on their personal WhatsApp number.
   - Zero vendor app/dashboard required.

4. **Single-Shop Cart Limitation**:
   - Cart allows items from **only one shop at a time**.
   - If user attempts to add an item from a different shop, app prompts to clear the current cart.

5. **Cloud Firestore as Single Source of Truth with Local Offline Fallback**:
   - Primary data fetched from Cloud Firestore.
   - Fallback dataset (`fallbackShops`, `rajatMenuItems`, `nayanMenuItems`) used ONLY if network is disconnected or Firestore query times out (3-second timeout).

6. **Manual Firestore Price Protection**:
   - `SeedDataService` must NEVER overwrite existing Firestore documents or manually edited prices on app startup.
