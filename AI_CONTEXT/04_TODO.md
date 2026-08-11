# 04 — TODO & Task Roadmap

## HIGH Priority (MVP Core — Data Architecture & Schema Freeze)
- [x] Finalize & freeze Firestore database schema (`shops`, `categories`, `menuItems` with `portionSize` & `isClosedOverride`).
- [x] Remove 100% of remaining hardcoded fallback shop/menu data from the codebase.
- [x] Enable native Firestore disk persistence cache (`Settings(persistenceEnabled: true)`).
- [x] Implement Riverpod `family` providers for lazy loading menu items and in-memory query caching.
- [x] Implement Shop Menu Category Navigation UI in `ShopDetailScreen` (horizontal circular dish photos, selected state indicators, sticky pinning via `SliverPersistentHeader`, Domino's/Swiggy-style auto scroll-spy category sync on scroll).
- [x] Connect Menu Category Selector to Cloud Firestore backend (`shops/{shopId}/categories`) for dynamic category addition, image updates, re-ordering, and active/inactive toggling without UI changes.
- [x] Display friendly floating toast alert ("No items currently available in [Category]") when tapping a 0-item category while skipping empty sections in vertical scrolling list.
- [x] Implement user-specific local Favorites feature on Menu Item Cards with `SharedPreferences` on-device persistence, Riverpod `favoritesProvider`, and zero Firestore writes.
- [x] Implement 4-tab Bottom Navigation (`Home` → `Favourites` → `Cart` → `Profile`) with Cart badge counter.
- [x] Implement Dedicated Favourites screen with food image, name, price, veg indicator, clear shop attribution, remove action, add-to-cart, and empty state.
- [x] Fix Cart lifetime decoupling from ShopDetailScreen: Cart persists across screen/tab navigation; cross-shop conflict protection preserved.
- [x] Implement Home category & status filter pills (`All`, `Open Now`, `Fast Food`, `Snacks`, `Thalis`, `Chinese`, `Veg`, `Non-Veg`).
- [x] Establish strict Profile (User info) vs Settings (App appearance & About) separation without UI duplication.

## MEDIUM Priority (MVP UI & Order Flow Polish)
- [x] Refine UI with Blinkit-inspired clean spacing, typography, and reusable component structure.
- [x] Update Shop Detail Screen: Display banner, shop name, description, plain-text contact number (non-clickable), open/closed status, category navigation, menu search, and items with `portionSize` details & out-of-stock support.
- [x] Update Cart Screen: Add "You may also like" item recommendation section (recommending items ONLY from the same shop).
- [ ] Verify live WhatsApp order delivery from student device at Bennett Gate No. 2.

## LOW Priority (Post-MVP / Future Expansion)
- [ ] Vendor Admin Panel (Web/Mobile dashboard for vendor document management).
- [ ] Promotional Banners & Coupons (Post-MVP).
- [ ] Lottie Animations & Advanced Search Auto-complete (Post-MVP).
