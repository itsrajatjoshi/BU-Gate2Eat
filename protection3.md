🔐 YummBU — Complete Security Audit Report

Auditor: Antigravity (acting as Senior Application Security Architect)
Scope: Full codebase inspection — Flutter client, Firestore Rules, Storage Rules, auth logic, role system, order lifecycle, seed data, panels, routing, dependencies, secrets
Date: 2026-08-28

Table of Contents

Current Security Architecture Summary

CRITICAL Vulnerabilities

HIGH-Risk Vulnerabilities

MEDIUM-Risk Vulnerabilities

LOW-Risk Vulnerabilities

Realistic Attack Scenarios

Recommended Architecture

Recommended Firestore Authorization Model

Recommended Backend Responsibilities

WhatsApp OTP Security Architecture

Admin Protection

Logging & Monitoring

Development vs Production Separation

Corrected Implementation Roadmap

Your Current Roadmap — What's Wrong

1. Current Security Architecture Summary

What Exists Today

Layer

Current State

Security Rating

Authentication

❌ None. Phone number entered in onboarding is stored in SharedPreferences. No verification, no OTP, no Firebase Auth.

🔴 ZERO

Authorization / Roles

❌ Client-side only. Hardcoded phone→role mapping in app_constants.dart. Role checked in Flutter UI only.

🔴 ZERO

Firestore Rules

⚠️ Partial. Order collection has good state-machine rules. But shops/categories/menuItems are world-writable. No request.auth checks anywhere.

🔴 CRITICAL

Storage Rules

⚠️ Partially restrictive. 1MB size + content-type checks exist. But no auth check — anyone can upload/delete to any shop folder.

🔴 CRITICAL

Route Guards

❌ None. /admin and /shopkeeper routes are accessible by directly entering the URL. No GoRouter redirect guard.

🟡 HIGH

Order Integrity

✅ Good. Firestore rules enforce valid initial order, immutable fields, valid state transitions. Client-side transaction logic is solid.

🟢 GOOD

Firebase App Check

❌ Not implemented.

🟡 MEDIUM

Session Security

❌ SharedPreferences-only. No token, no expiry, no revocation.

🔴 CRITICAL

Secrets Management

⚠️ API key + google-services.json committed to git. Firebase options hardcoded.

🟡 HIGH

Error Handling

⚠️ debugPrint throughout with Firestore paths, stack traces. Will leak in production.

🟡 MEDIUM

The Core Problem

There is currently ZERO authentication. Anyone who knows the admin phone number (8078643910) can type it during onboarding and get full admin access. The entire role system is a client-side illusion — it provides no actual security whatsoever.

2. CRITICAL Vulnerabilities

These MUST be fixed before any public/semi-public release. Each one alone can destroy the platform.

C-1: 🔴 No Authentication — Complete Identity Forgery

File: onboarding_screen.dart

Problem: User types any phone number → it's saved to SharedPreferences → the app trusts it forever. No OTP, no verification, no Firebase Auth.

Attack:

1. Download the app
2. Enter phone number: 8078643910 (admin phone, hardcoded in source)
3. Get full admin access
4. Delete all shops, all menus, all orders

Impact: Complete platform takeover. Any person can become admin, any shopkeeper, or impersonate any customer.

Why it's critical: This isn't a future concern — this is the CURRENT state. If anyone installs the app and enters the admin phone, they own everything.

C-2: 🔴 Shops/Categories/Menu Items Are World-Writable

File: firestore.rules

match /shops/{shopId} {
  allow read: if true;
  allow create, update: if isValidShopWrite();   // Only checks name exists!
  allow delete: if true;                          // ANYONE CAN DELETE ANY SHOP!
  
  match /categories/{categoryId} {
    allow delete: if true;                        // ANYONE CAN DELETE CATEGORIES!
  }
  
  match /menuItems/{menuItemId} {
    allow delete: if true;                        // ANYONE CAN DELETE MENU ITEMS!
  }
}

Attack: Using any Firebase REST client, a Postman-like tool, or even the browser console on the web app:

// Delete a shop entirely
firebase.firestore().collection('shops').doc('rajat_shop').delete();

// Change all prices to ₹0
firebase.firestore().collection('shops').doc('rajat_shop')
  .collection('menuItems').doc('veg_steam_momos')
  .update({price: 0, name: 'FREE MOMOS'});

Impact: Complete menu/shop data destruction. Competitor sabotage. Price manipulation.

C-3: 🔴 Orders Are World-Readable

File: firestore.rules

allow read: if true;    // ANY person can read ALL orders from ALL customers

Attack: Query the orders collection to get every customer's name, phone number, order history, and special instructions.

Impact: Complete customer privacy violation. Phone numbers + names + ordering habits = personal data leak. This is also a potential legal issue under Indian data protection laws.

C-4: 🔴 Client-Side Role System Is Security Theater

File: app_constants.dart

class AppAuthRoles {
  static const String adminPhone = '8078643910';
  
  static const Map<String, String> shopkeeperPhoneMap = {
    '8295643910': 'rajat_shop',
    '8875344034': 'nayan_shop',
    // ... all phone numbers hardcoded and visible in the APK
  };
}

Problems:

Admin phone number is hardcoded in the compiled app — extractable via apktool, jadx, or simple string search on the APK

All shopkeeper phone numbers and their shop assignments are embedded in client code

The endsWith matching in isShopkeeperPhone means ANY phone ending in 643910 would match!

No server-side validation exists — Firestore rules don't check request.auth at all

C-5: 🔴 Storage Is Unauthenticated — Anyone Can Upload/Delete Images

File: storage.rules

match /shops/{shopId}/{allPaths=**} {
  allow create, update: if request.resource.size < 1 * 1024 * 1024
                        && request.resource.contentType.matches('image/.*');
  allow delete: if true;
}

Attack: Upload inappropriate images to any shop's folder. Delete all shop images. Replace banners with competitor logos or offensive content.

C-6: 🔴 google-services.json Committed to Git

Found via: git ls-files --cached → android/app/google-services.json

This file contains your Firebase project ID, API keys, and client IDs. While Firebase API keys are designed to be somewhat public (controlled by app restrictions), committing this file means:

Any contributor or anyone with repo access has your Firebase project credentials

Combined with the wide-open Firestore/Storage rules, this gives complete read/write access to your entire database

3. HIGH-Risk Vulnerabilities

H-1: 🟠 No Route Guards — Direct URL Access to Admin/Shopkeeper

File: router.dart

No redirect callback on the GoRouter. On the web app, typing /#/admin or /#/shopkeeper in the URL bar renders the full admin/shopkeeper UI.

[!WARNING]
Even after adding route guards, this is NOT real security. Route guards are UX helpers, not security barriers. The real fix is authenticated Firestore rules.

H-2: 🟠 Order Reads Have No Ownership Check

File: order_service.dart

The client-side watchCustomerActiveOrders filters by customerId, but the Firestore rule is allow read: if true. A malicious client can query ALL orders, not just their own.

Attack: Skip the client filter → read ALL customer orders → harvest phone numbers and names.

H-3: 🟠 ShopStats Writable by Anyone

File: firestore.rules

match /shopStats/{shopId} {
  allow read: if true;
  allow create, update: if isValidShopStatsWrite(shopId);
}

Only checks data.shopId == shopId. Anyone can write fake stats to any shop — inflating or deflating order counts, accepted counts, etc.

H-4: 🟠 Seed Data Service Runs on Every App Launch

File: seed_data_service.dart

While it uses if (!doc.exists) guards, this service:

Is compiled into the production APK

Contains all shop data, contact numbers, and menu prices in plaintext

The _backfillMissingShopFields function can write to Firestore without auth

Risk: Development code in production. Even though it doesn't overwrite existing data, it's unnecessary attack surface and information disclosure.

H-5: 🟠 Customer Identity Derived from Self-Reported Phone

File: local_storage_service.dart

String get customerId {
  final phone = userPhone.trim();
  if (phone.isNotEmpty) {
    return 'cust_$phone';   // Anyone who types YOUR phone = becomes YOU
  }
}

Since customerId is cust_<phone> and there's no auth verification, anyone entering your phone number can place orders as you, see your orders (once rules are added with ownership), and impersonate you.

H-6: 🟠 Debug Prints Leak Firestore Paths and Internal Details

Files: Throughout firestore_service.dart, order_service.dart

debugPrint('📝 FirestoreService.updateShop -> updating shops/$shopId with: $updateData');
debugPrint('❌ OrderService updateOrderStatus error: $e');

On web builds and rooted Android, these logs are accessible. They reveal:

Firestore collection paths

Document IDs

Error details including stack traces

Storage bucket names

4. MEDIUM-Risk Vulnerabilities

M-1: 🟡 No Rate Limiting on Order Creation

Current state: Firestore rules allow unlimited order creation as long as fields are valid. No client-side or server-side throttle.

Attack: Script that creates 10,000 fake orders in 1 minute. Each shopkeeper gets spammed. No way to stop it without manually deleting.

M-2: 🟡 No Firebase App Check

Current state: Any HTTP client can directly access your Firestore and Storage using the public API key and project ID.

What App Check does: Attests that requests come from your legitimate app binary (using Play Integrity on Android, reCAPTCHA on web).

What it does NOT do: It does NOT replace authentication. It just makes direct curl/Postman attacks harder.

M-3: 🟡 No Input Sanitization on Order Special Instructions

File: order_model.dart

specialInstructions can contain up to 200 chars of arbitrary text (enforced client-side). On web, this could be used for XSS if ever rendered as HTML.

M-4: 🟡 Shopkeeper Shell Uses Duplicate Phone-to-Shop Mapping

File: shopkeeper_main_shell.dart

The shop resolution logic is duplicated from AppAuthRoles and hardcoded again with different logic (endsWith patterns). This creates maintenance drift and potential authorization bypass if one is updated but not the other.

M-5: 🟡 No Order Quantity Limits

Client-side cart allows arbitrary quantities. Firestore rules check items.size() > 0 and totalAmount > 0 but don't cap quantity per item or total items per order.

Attack: Place an order for 999,999 momos at ₹59,999,940.

M-6: 🟡 Client-Side Price Calculation Not Verified Server-Side

File: order_service.dart

createOrder writes whatever totalAmount the client sends. Firestore rules only check totalAmount > 0. There is no server-side recalculation from the actual menu prices.

Attack: Order ₹500 worth of food, modify the request to say totalAmount = 1. Order is created with ₹1 total.

5. LOW-Risk Vulnerabilities

L-1: 🔵 Firebase API Key Hardcoded in Source

File: firebase_options.dart

Firebase API keys in client apps are expected to be public and are controlled via Firebase console restrictions. However, the key AIzaSyC0M9efTmOQFzHFxiva7NZcwPuTHJJuB8c should have:

HTTP referrer restrictions (for web)

Android app restrictions (for mobile)

API restrictions (only Firestore, Storage, Auth)

L-2: 🔵 No Code Obfuscation in Release Build

Dart AOT compilation provides some natural obfuscation, but adding --obfuscate --split-debug-info=symbols/ to the build command makes reverse engineering significantly harder.

L-3: 🔵 server.py — Development Web Server in Production Codebase

File: server.py

A basic Python HTTP server with no-cache headers. Not a security risk itself, but should be in a tools/ or .dev/ directory, not project root.

L-4: 🔵 Unsplash URLs as Default Images

The seed data and default category image use Unsplash URLs. These could change, rate-limit, or go down. Not a security risk, but an availability risk.

6. Realistic Attack Scenarios Specific to YummBU

Scenario 1: "The Curious Student" — Complete Platform Takeover (5 minutes)

Step 1: Download APK or open web app
Step 2: Use apktool or browser DevTools to find:
        - Admin phone: 8078643910
        - Firebase project: bu-gate2eat
        - API key: AIzaSyC0M9efTmOQFzHFxiva7NZcwPuTHJJuB8c
Step 3: Open onboarding, enter 8078643910
Step 4: Full admin access. Delete all shops.

OR

Step 3b: Open Firebase console (public project ID)
Step 4b: Use REST API to write directly to Firestore:
         - Delete all shops
         - Change all prices
         - Read all customer phone numbers
         - Create fake orders

Current defense: ❌ None.

Scenario 2: "The OTP Bill Bomber" (Post-Authentication)

Step 1: Write a script that hits the WhatsApp OTP endpoint
Step 2: Send OTP requests for 10,000 different phone numbers
Step 3: Each OTP costs ₹0.50-2.00
Step 4: Monthly bill: ₹5,000-20,000+ for no legitimate usage

Current defense: ❌ No OTP system exists yet. Must be designed with rate limiting from day one.

Scenario 3: "The Competitor Saboteur"

Step 1: Use Postman + Firebase API key
Step 2: Update shop document: set isClosedOverride = true
Step 3: Shop appears permanently closed to all customers
Step 4: Delete all menu items for a competing shop
Step 5: Upload offensive images to shop banner

Current defense: ❌ Firestore/Storage rules allow all of this.

Scenario 4: "The Free Food Student"

Step 1: Intercept order creation request
Step 2: Change totalAmount from 500 to 1
Step 3: Keep items the same
Step 4: Order is created with ₹1 total
Step 5: Shopkeeper sees ₹1 order but items worth ₹500

Current defense: ⚠️ Firestore rules check totalAmount > 0 but don't verify it matches item prices.

Scenario 5: "The Phone Number Harvester"

Step 1: Query Firestore orders collection (public read)
Step 2: Extract all unique customerPhone values
Step 3: Get a database of Bennett University student phone numbers
Step 4: Use for spam, phishing, or sale

Current defense: ❌ Orders are world-readable.

7. Recommended Architecture

graph TB
    subgraph "Client Layer (UNTRUSTED)"
        A["Flutter App (Android/Web)"]
        B["UI Route Guards"]
        C["Client-Side Validation"]
    end

    subgraph "Attestation Layer"
        D["Firebase App Check"]
    end

    subgraph "Authentication Layer"
        E["Firebase Auth (Custom Token)"]
        F["WhatsApp OTP Backend"]
    end

    subgraph "Authorization Layer"
        G["Firestore Security Rules"]
        H["Storage Security Rules"]
        I["Custom Claims (role, shopId)"]
    end

    subgraph "Backend (TRUSTED)"
        J["Cloud Functions / Secure Backend"]
        K["Order Price Recalculation"]
        L["OTP Rate Limiting"]
        M["Admin Action Audit Log"]
        N["Role/Claim Management"]
    end

    subgraph "Data Layer"
        O["Firestore Database"]
        P["Firebase Storage"]
    end

    A --> D
    D --> E
    E --> G
    E --> H
    G --> O
    H --> P
    A --> J
    J --> O
    J --> P
    F --> E

Key Architectural Decisions

Decision

Recommendation

Reason

Role storage

Firebase Auth Custom Claims (role: 'admin', shopId: 'rajat_shop')

Cannot be forged client-side. Embedded in the auth token. Checked by Firestore rules via request.auth.token.role.

Order creation

Cloud Function (callable)

Server recalculates totalAmount from actual menu prices. Prevents client-side price manipulation.

Shop/menu writes

Cloud Function for admin/shopkeeper operations

Never let the client directly write to shops/menuItems.

OTP

Secure backend → WhatsApp API → verify → mint Firebase custom token

OTP secrets never touch the client. Rate limiting enforced server-side.

App Check

Enable for Firestore + Storage + Cloud Functions

Blocks casual REST API attacks. Not bulletproof but raises the bar significantly.

8. Recommended Firestore Authorization Model

After Authentication Is Implemented

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ─── HELPER FUNCTIONS ────────────────────────────
    function isSignedIn() {
      return request.auth != null;
    }
    
    function isAdmin() {
      return isSignedIn() && request.auth.token.role == 'admin';
    }
    
    function isShopkeeper(shopId) {
      return isSignedIn() 
          && request.auth.token.role == 'shopkeeper'
          && request.auth.token.shopId == shopId;
    }
    
    function isShopkeeperOfAnyShop() {
      return isSignedIn() && request.auth.token.role == 'shopkeeper';
    }
    
    function isOwner(customerId) {
      return isSignedIn() && request.auth.uid == customerId;
    }

    // ─── ORDERS ──────────────────────────────────────
    match /orders/{orderId} {
      // Customer: only their own orders
      // Shopkeeper: only their shop's orders  
      // Admin: all orders
      allow read: if isAdmin()
                  || (isSignedIn() && resource.data.customerId == request.auth.uid)
                  || isShopkeeper(resource.data.shopId);
      
      // Create: authenticated user, status must be 'placed'
      allow create: if isSignedIn() 
                    && request.resource.data.customerId == request.auth.uid
                    && isValidInitialOrder();
      
      // Update: shopkeeper (status transitions) or admin
      allow update: if (isShopkeeper(resource.data.shopId) || isAdmin())
                    && areImmutableFieldsPreserved()
                    && isValidStatusTransition();
      
      // Delete: customer can cancel 'placed', admin can clean terminal
      allow delete: if (isOwner(resource.data.customerId) && resource.data.status == 'placed')
                    || (isAdmin() && isAllowedOrderDeletion());
    }

    // ─── SHOPS ───────────────────────────────────────
    match /shops/{shopId} {
      allow read: if true;    // Public menu browsing
      allow write: if isAdmin() || isShopkeeper(shopId);
      allow delete: if isAdmin();
      
      match /categories/{catId} {
        allow read: if true;
        allow write: if isAdmin() || isShopkeeper(shopId);
        allow delete: if isAdmin() || isShopkeeper(shopId);
      }
      
      match /menuItems/{itemId} {
        allow read: if true;
        allow write: if isAdmin() || isShopkeeper(shopId);
        allow delete: if isAdmin() || isShopkeeper(shopId);
      }
    }

    // ─── SHOP STATS ──────────────────────────────────
    match /shopStats/{shopId} {
      allow read: if true;
      allow write: if false;  // Only via Cloud Functions
    }

    // ─── CONFIG ──────────────────────────────────────
    match /config/{doc=**} {
      allow read: if true;
      allow write: if false;  // Only via Firebase Console or Cloud Functions
    }

    // ─── DEFAULT DENY ────────────────────────────────
    match /{document=**} {
      allow read, write: if false;
    }
  }
}

9. Recommended Backend Responsibilities

What MUST go through a backend (Cloud Function or server)

Operation

Why

Order creation

Server must recalculate totalAmount from actual Firestore menu prices. Client-provided total cannot be trusted.

OTP send/verify

WhatsApp API secrets must never touch the client. Rate limiting must be server-side.

Firebase custom token minting

After OTP verification, server creates a Firebase Auth token with custom claims (role, shopId).

Role assignment/change

Admin assigns shopkeeper role → server sets custom claim. Never client-side.

ShopStats updates

Move from client transaction to Cloud Function trigger (onUpdate of orders). Prevents stat manipulation.

Admin delete operations

Audit log + confirmation through backend.

Image validation (optional)

Server-side check for inappropriate content if budget allows.

What can stay client-side (direct Firestore)

Operation

Why it's OK

Read public shop/menu data

Public information, no harm in reading.

Read own orders

Protected by resource.data.customerId == request.auth.uid in rules.

Shopkeeper updating item availability

Protected by isShopkeeper(shopId) in rules.

Shopkeeper accepting/rejecting orders

Protected by rules + state machine validation.

10. WhatsApp OTP Security Architecture

Recommended Flow

sequenceDiagram
    participant C as Flutter Client
    participant B as Secure Backend
    participant W as WhatsApp API Provider
    participant FA as Firebase Auth

    C->>B: POST /auth/request-otp {phone: "9876543210"}
    
    Note over B: Rate limit checks:<br/>- Per phone: 3/hour, 5/day<br/>- Per IP: 10/hour<br/>- Global: 500/day<br/>- Cooldown: 60s between requests
    
    B->>B: Generate 6-digit OTP, store with expiry (5 min)
    B->>W: Send OTP via WhatsApp
    W-->>C: User receives OTP on WhatsApp
    
    C->>B: POST /auth/verify-otp {phone, otp}
    
    Note over B: Verify checks:<br/>- Max 5 attempts per OTP<br/>- OTP not expired<br/>- OTP matches<br/>- Lockout after 5 failures (15 min)
    
    B->>B: Look up role for phone number
    B->>FA: createCustomToken(uid, {role, shopId})
    FA-->>B: Firebase Custom Token
    B-->>C: {token: "firebase_custom_token"}
    
    C->>FA: signInWithCustomToken(token)
    Note over C: Now has authenticated Firebase session<br/>with custom claims (role, shopId)

OTP Rate Limiting Table

Limit

Value

Enforcement

Cooldown between OTP requests (same phone)

60 seconds

Backend

Max OTPs per phone per hour

3

Backend (Redis/Firestore counter)

Max OTPs per phone per day

5

Backend

Max OTPs per IP per hour

10

Backend / API Gateway

Max wrong attempts per OTP

5

Backend (then invalidate OTP)

Lockout after max wrong attempts

15 minutes

Backend

OTP expiry

5 minutes

Backend

Global daily OTP cap (emergency)

500 (adjustable)

Backend + alert

Global monthly cost cap

₹2,000 (alert at ₹1,500)

Backend + alert

OTP Cost Protection

Monthly Students

Est. OTP/month

Cost (₹1/OTP)

With Attack

500

~1,500

₹1,500

Without limits: ₹50,000+

The rate limiting alone can reduce attack cost to near-zero while keeping legitimate usage smooth.

11. Admin Protection

Current State

Admin is identified by a hardcoded phone number. No special protection whatsoever.

Recommended Layered Protection

Layer

Implementation

Priority

Custom Claims

role: 'admin' in Firebase Auth token. Cannot be set client-side.

CRITICAL

Re-authentication for sensitive actions

Before deleting a shop or changing a shopkeeper assignment, require OTP re-verification

HIGH

Multi-admin support

Store admin UIDs in a protected Firestore collection readable only by admins

HIGH

Session timeout

Admin sessions expire after 24 hours (vs 30 days for customers)

MEDIUM

Audit logging

Every admin action (create/delete shop, change role, reset stats) logged with timestamp + IP

HIGH

Emergency lockout

Ability to revoke all admin tokens via Firebase Console

MEDIUM

Future MFA

TOTP or push-notification-based second factor for admin login

LOW (Phase 3+)

12. Logging & Monitoring

What to Log (Cost-Efficient)

Event

Where to Log

Priority

Admin creates/deletes shop

Firestore audit_log collection

CRITICAL

Admin changes shopkeeper assignment

Firestore audit_log

CRITICAL

Failed OTP attempts (>3 for same phone)

Backend log + alert

HIGH

OTP daily spend threshold crossed

Backend alert (email/Slack)

HIGH

Order status transitions

Already in order document (good)

✅ EXISTS

Firestore rule denials

Firebase Console → automatic

✅ FREE

Unusual order volume (>50 orders/hour for a shop)

Cloud Function monitor

MEDIUM

What NOT to Log (Cost Control)

❌ Every menu item view

❌ Every cart add/remove

❌ Every page navigation

❌ Normal successful reads

Estimated Cost

Firestore audit_log writes: ~100-500/day = practically free tier

Backend logs (Cloud Run/Functions): included in free tier for low volume

Firebase Console metrics: free

13. Development vs Production Separation

Current Dangers

Item

Risk

Fix

Seed data service in production APK

Information disclosure

Compile-time flag: if (kDebugMode)

debugPrint everywhere

Log leaks on web/rooted devices

Replace with a logging service that's silent in release

Admin phone hardcoded

Extractable from APK

Move to Firestore config or custom claims

Shopkeeper phones hardcoded

Extractable from APK

Move to Firestore shopkeepers collection

No separate Firebase project

Dev testing writes to production

Create bu-gate2eat-dev project

Recommended Environment Strategy

Development:
├── Firebase project: bu-gate2eat-dev
├── Test phone numbers: 9999900001-9999900010
├── Firestore rules: allow if true (for testing)
├── OTP: Mock/bypass in dev mode
└── Seed data: runs freely

Staging:
├── Firebase project: bu-gate2eat (or bu-gate2eat-staging)
├── Firestore rules: production rules
├── OTP: Real but with test phone whitelist
└── Seed data: disabled

Production:
├── Firebase project: bu-gate2eat
├── Firestore rules: production rules (locked)
├── OTP: Real with full rate limiting
├── Seed data: COMPLETELY REMOVED from build
├── Debug prints: SILENT
└── App Check: ENFORCED

14. Corrected Implementation Roadmap

[!IMPORTANT]
Your current roadmap has the authentication in Phase 3 — this is fundamentally wrong. Authentication MUST come first because every other security layer depends on request.auth in Firestore rules.

PHASE 0 — PRE-SECURITY CLEANUP (1-2 days)

0.1 Remove hardcoded phone numbers from client code
    → Move to env config or Firestore (admin-only readable)
0.2 Wrap seed data in kDebugMode guard
0.3 Replace debugPrint with a production-safe logger
0.4 Add --obfuscate to release build
0.5 Add google-services.json to .gitignore
    → Remove from git history with git filter-branch
0.6 Restrict Firebase API key in Google Cloud Console

PHASE 1 — AUTHENTICATION (1-2 weeks) ⚡ MOVED UP FROM PHASE 3

1.1 Set up secure backend (Cloud Functions or Cloud Run)
1.2 Implement WhatsApp OTP send endpoint with rate limiting
1.3 Implement OTP verify endpoint
1.4 Implement Firebase custom token minting with role claims
1.5 Update Flutter app: replace onboarding with OTP login flow
1.6 Update customerIdentityProvider to use Firebase Auth UID
1.7 Add session management: logout, token refresh
1.8 Add dev-mode bypass for testing (mock OTP)

PHASE 2 — FIRESTORE & STORAGE AUTHORIZATION (1 week)

2.1 Deploy authenticated Firestore rules (shops, orders, stats)
2.2 Deploy authenticated Storage rules
2.3 Add route guards in GoRouter (redirect unauthenticated)
2.4 Test: customer cannot read other customers' orders
2.5 Test: shopkeeper cannot access another shop
2.6 Test: anonymous user cannot write to shops/menu

PHASE 3 — ORDER SECURITY & BACKEND (1 week)

3.1 Create Cloud Function for order creation
    → Server-side price recalculation from actual menu prices
    → Validate items exist and are available
    → Enforce quantity limits
3.2 Move shopStats updates to Cloud Function triggers
3.3 Add order spam protection (max 5 active orders per customer)
3.4 Add admin audit logging Cloud Function

PHASE 4 — HARDENING (3-5 days)

4.1 Enable Firebase App Check (Android: Play Integrity, Web: reCAPTCHA)
4.2 Run in monitor mode for 1 week before enforcement
4.3 Add admin re-authentication for sensitive actions
4.4 Input sanitization review
4.5 Error message sanitization (no internal paths in user-facing errors)

PHASE 5 — TESTING & LAUNCH (3-5 days)

5.1 Security test: attempt all 5 attack scenarios manually
5.2 Test with Firebase Emulator Suite
5.3 Review all rules with Firebase Rules Playground
5.4 Dependency audit (flutter pub outdated)
5.5 Final production configuration review
5.6 Create incident response document
5.7 Launch

15. Your Current Roadmap — What's Wrong

Your Phase

Issue

Fix

Phase 1.1: Role System

✅ Correct to start here

But it must include authentication — roles without auth are meaningless

Phase 1.2: Route Security

🟡 Nice-to-have but NOT security

Move to Phase 2 as a UI improvement

Phase 1.3: Firestore Security

✅ Critical

But requires auth first — rules using request.auth need Firebase Auth

Phase 1.4: Order Security

✅ Correct

Needs backend Cloud Function for price verification

Phase 1.5: Storage Security

✅ Correct

Requires auth for shopkeeper upload rules

Phase 2.6: Spam Protection

✅ Correct placement

—

Phase 2.7: Production Cleanup

🔴 TOO LATE!

Move to Phase 0. Hardcoded phones must be removed FIRST.

Phase 2.8: Security Testing

✅ Correct

—

Phase 3.1: WhatsApp OTP

🔴 WAY TOO LATE!

Must be Phase 1. Everything depends on authentication.

Phase 3.2: OTP Rate Limits

✅ Correct

Part of Phase 1

Phase 3.3: Backend

🔴 TOO LATE!

Backend is needed for auth AND order security. Move to Phase 1.

Phase 3.5: Session Security

Part of auth

Move to Phase 1

Phase 3.6: Error Messages

✅ Fine placement

—

Phase 3.7: Logging

✅ Fine placement

—

Phase 3.8: Admin MFA

✅ Correct as final phase

—

Missing Items

Missing

Priority

Where

Remove hardcoded credentials from client

CRITICAL

Phase 0

google-services.json removal from git

CRITICAL

Phase 0

API key restrictions in Google Cloud Console

HIGH

Phase 0

Server-side price recalculation

HIGH

Phase 3

Firebase Emulator Suite for testing

MEDIUM

Phase 5

Incident response plan

MEDIUM

Phase 5

Code obfuscation

LOW

Phase 0

Unnecessary/Overkill Items for Current Stage

Item

Verdict

Multi-device session limit (4 devices for shopkeeper)

🔵 OVERKILL for now. Simple "log out other sessions" button is enough.

Complex per-IP rate limiting

🔵 OVERKILL. Per-phone + global limits are sufficient. Indian mobile IPs are shared/rotated.

Image content moderation (AI)

🔵 OVERKILL. Manual review is fine for 4 shops.

Real-time intrusion detection

🔵 OVERKILL. Firebase Console metrics + simple alerts are enough.

[!CAUTION]
The single most important takeaway: Authentication must be implemented FIRST. Without it, Firestore rules cannot distinguish between a customer, shopkeeper, and admin. Every other security measure is built on top of knowing WHO the user actually is. Your current roadmap has authentication at Phase 3 — this must become Phase 1.

[!TIP]
Good news: Your order lifecycle logic (state machine, immutable fields, atomic transactions) is genuinely well-designed. Once authentication is added, the order security will be strong. The Firestore rules for orders just need request.auth checks added to the existing validation functions.