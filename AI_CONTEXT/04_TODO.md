# 04 — TODO & Task Roadmap

## HIGH Priority (MVP Core — Data Architecture & Schema Freeze)
- [x] Finalize & freeze Firestore database schema (`shops`, `categories`, `menuItems` with `portionSize` & `isClosedOverride`).
- [x] Remove 100% of remaining hardcoded fallback shop/menu data from the codebase.
- [x] Enable native Firestore disk persistence cache (`Settings(persistenceEnabled: true)`).
- [x] Implement Riverpod `family` providers for lazy loading menu items and in-memory query caching.
- [x] Implement Shop Menu Category Navigation UI in `ShopDetailScreen` (horizontal circular dish photos, selected state indicators, sticky pinning via `SliverPersistentHeader`, Domino's/Swiggy-style auto scroll-spy category sync on scroll).

## MEDIUM Priority (MVP UI & Order Flow Polish)
- [x] Refine UI with Blinkit-inspired clean spacing, typography, and reusable component structure.
- [x] Update Shop Detail Screen: Display banner, shop name, description, plain-text contact number (non-clickable), open/closed status, category navigation, menu search, and items with `portionSize` details & out-of-stock support.
- [x] Update Cart Screen: Add "You may also like" item recommendation section (recommending items ONLY from the same shop).
- [ ] Verify live WhatsApp order delivery from student device at Bennett Gate No. 2.

## LOW Priority (Post-MVP / Future Expansion)
- [ ] Vendor Admin Panel (Web/Mobile dashboard for vendor document management).
- [ ] Promotional Banners & Coupons (Post-MVP).
- [ ] Lottie Animations & Advanced Search Auto-complete (Post-MVP).
