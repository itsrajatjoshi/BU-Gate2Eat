# 04 — TODO & Task Roadmap

## HIGH Priority (MVP Core — Data Architecture & Schema Freeze)
- [ ] Finalize & freeze Firestore database schema (`shops`, `categories`, `menuItems` with `portionSize` & `isClosedOverride`).
- [ ] Remove 100% of remaining hardcoded fallback shop/menu data from the codebase.
- [ ] Enable native Firestore disk persistence cache (`Settings(persistenceEnabled: true)`).
- [ ] Implement Riverpod `family` providers for lazy loading menu items and in-memory query caching.

## MEDIUM Priority (MVP UI & Order Flow Polish)
- [ ] Refine UI with Blinkit-inspired clean spacing, typography, and reusable component structure.
- [ ] Update Shop Detail Screen: Display banner, shop name, description, plain-text contact number (non-clickable), open/closed status, category tabs, menu search, and items with `portionSize` details & out-of-stock support.
- [ ] Update Cart Screen: Add "You may also like" item recommendation section (recommending items ONLY from the same shop).
- [ ] Verify live WhatsApp order delivery from student device at Bennett Gate No. 2.

## LOW Priority (Post-MVP / Future Expansion)
- [ ] Vendor Admin Panel (Web/Mobile dashboard for vendor document management).
- [ ] Promotional Banners & Coupons (Post-MVP).
- [ ] Lottie Animations & Advanced Search Auto-complete (Post-MVP).
