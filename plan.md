Maine teenon documents ko **compare karke deeply analyze** kiya hai:

1. **Original security roadmap** — tumhara initial Phase 1 → Phase 2 → Phase 3 plan. 
2. **Architecture/Claude-style review** — isne sabse important architectural problems aur roadmap-order issues identify kiye. 
3. **Actual codebase audit report** — isme existing files, Firestore rules, Storage rules, onboarding, role system, routes, seed data etc. ke concrete issues identify kiye gaye. 

## Sabse important conclusion

**Teenon documents ka core conclusion same hai:**

> YummBU ka sabse bada current problem UI nahi hai.
> **Problem hai ki app abhi user ko reliably identify nahi karta, aur Firebase/backend level par permissions properly enforce nahi ho rahi hain.**

Lekin ek important distinction hai:

* Architecture review ne kuch risks **possible/design-level risks** ke roop mein bataye.
* Actual audit report ne kuch vulnerabilities ko **current codebase mein existing** bataya. For example: no real authentication, client-side phone→role mapping, world-readable orders, world-writable shop/menu areas, unauthenticated Storage, no route guards, etc. 

---

# 🚨 Pehle: tumhari original roadmap mein kya problem thi?

Tumhara original order tha roughly:

```text
Phase 1
Role
↓
Routes
↓
Firestore
↓
Orders
↓
Storage

Phase 2
Spam
↓
Cleanup
↓
Audit

Phase 3
WhatsApp OTP
↓
Backend
↓
Sessions
↓
Admin protection
```

Architecture review ka strongest objection tha:

> **Authentication aur backend ko itna late nahi hona chahiye.**

Kyunki Firestore rules ko ultimately yeh pata hona chahiye:

```text
Ye request kis user ne bheji?
↓
Uska real UID kya hai?
↓
Uska role kya hai?
↓
Kya woh is particular shop/order ko access kar sakta hai?
```

Sirf Flutter ke andar:

```text
if role == admin
```

karna actual security nahi hai. 

---

# 🔥 FINAL PROBLEM LIST — Priority ke hisaab se

Main problems ko 5 groups mein divide kar raha hoon.

---

# GROUP A — IDENTITY & ACCESS PROBLEMS 🔴

## Problem 1 — Real authentication nahi hai

Audit ke according currently user onboarding mein phone number enter karta hai aur woh local storage mein save ho jata hai. OTP/Firebase Auth verification nahi hai. 

### Attack

Koi bhi theoretically admin ka phone number enter karke:

```text
Customer
↓
Admin phone enter
↓
Admin UI/access
```

try kar sakta hai.

### Solution

Final production architecture:

```text
WhatsApp Number
        ↓
Secure Backend
        ↓
OTP send
        ↓
OTP verify
        ↓
Firebase authenticated identity
        ↓
UID
        ↓
Role check
        ↓
Customer / Shopkeeper / Admin
```

### Priority

🔴 **Launch blocker**

---

## Problem 2 — Role system client-side hai

Current audit ke according admin aur shopkeeper phone mapping client code mein hardcoded hai. 

Simple problem:

```text
Flutter says:
"I am admin"
```

is not enough.

### Solution

Actual authority:

```text
Authenticated UID
        ↓
Trusted role assignment
        ↓
Custom Claims / trusted authorization
        ↓
Firestore Rules + Backend
```

User khud apna role change nahi kar sakega.

---

## Problem 3 — Shopkeeper sirf shopkeeper hona enough nahi

Correct check:

❌

```text
role = shopkeeper
```

because then theoretically:

```text
Shopkeeper A
↓
Changes shopId
↓
Tries Shop B
```

Correct model:

```text
User UID
+
role = shopkeeper
+
authorized shop assignment
=
permission
```

Ye architecture review ka critical point tha. 

---

# GROUP B — FIRESTORE & DATA SECURITY 🔴

## Problem 4 — Shops/menu/categories current audit ke according too open hain

Audit mein shop/category/menu delete aur write permissions dangerously broad report hui hain. 

### Risk

Koi attacker:

* Shop delete
* Menu delete
* Price ₹0
* Item name change
* Shop closed/open manipulate

kar sakta hai if rules truly as audited deployed hain.

### Solution

**Deny by default** model:

```text
Nobody gets access
        ↓
Explicit permission required
```

Example conceptually:

| User       | Shop                   | Menu                   | Orders             |
| ---------- | ---------------------- | ---------------------- | ------------------ |
| Customer   | Public read            | Public read            | Only own           |
| Shopkeeper | Assigned shop only     | Assigned shop only     | Assigned shop only |
| Admin      | Authorized full access | Authorized full access | Authorized access  |

The authorization matrix should become the basis for actual rules. 

---

## Problem 5 — Customer orders world-readable hain

Actual audit reports:

```text
allow read: if true
```

for orders. 

### Risk

Someone could potentially access:

* Customer names
* Phone numbers
* Order history
* Special instructions

### Solution

```text
Customer A
→ only Customer A orders

Shopkeeper A
→ only Shop A orders

Admin
→ authorized admin access
```

Rules should use actual authenticated identity and document ownership.

---

## Problem 6 — ShopStats manipulation

Audit says shop statistics can currently be written based mainly on shopId consistency rather than actual authorization. 

### Risk

Fake:

* Order count
* Revenue/statistics
* Accepted/rejected counts

### Solution

Move authoritative stats updates away from normal clients:

```text
Order changes
      ↓
Trusted backend / Cloud Function
      ↓
ShopStats update
```

Client should not directly control business statistics.

---

# GROUP C — ORDER SECURITY 🔴

## Problem 7 — Client price should never be trusted

Even if Flutter calculates correctly:

```text
Burger ₹100 × 2
= ₹200
```

attacker can theoretically send:

```text
totalAmount = ₹1
```

Architecture review repeatedly identifies this as a major business-logic risk. 

### Correct solution

Flutter sends only something like:

```text
shopId
itemId
quantity
specialInstructions
```

Trusted backend:

```text
Receives request
↓
Fetches real menu item
↓
Checks availability
↓
Checks quantity
↓
Uses actual price
↓
Calculates final amount
↓
Creates order
```

**Client total = display value only.**
**Server total = actual authoritative value.**

---

## Problem 8 — Order status manipulation

Customer should not be able to do:

```text
placed → delivered
```

Shopkeeper should not be able to randomly do:

```text
rejected → accepted
```

Correct state machine:

```text
PLACED
 ├── ACCEPTED
 │       └── DELIVERED
 │
 ├── REJECTED
 │
 └── CANCELLED
```

And each transition must verify:

```text
Current status
+
Who is performing action
+
Which shop/order belongs to them
+
Requested new status
```

The architecture review specifically treats this as a server/rules authorization boundary. 

---

## Problem 9 — Duplicate/replay orders

Current UI double-tap protection alone is not enough.

Scenario:

```text
Place Order
click click click click
```

or same request replayed.

### Solution

Multiple layers:

```text
UI submission lock
+
backend idempotency / duplicate detection
+
reasonable rate limit
```

This should be implemented together with order creation, not months later. 

---

# GROUP D — STORAGE & FILE SECURITY 🔴

## Problem 10 — Storage authentication missing

Current audit reports that image upload/delete permissions lack authentication checks. 

### Risk

Potentially:

```text
Customer
↓
Uploads random image

Attacker
↓
Deletes banner

Competitor
↓
Replaces shop image
```

### Solution

```text
Customer
→ read public images only

Shopkeeper
→ write/delete own assigned shop files only

Admin
→ authorized management
```

Plus:

* Allowed MIME types
* Maximum size
* Correct folder path
* Controlled overwrite
* Controlled delete
* Orphan image cleanup



---

# GROUP E — DEVELOPMENT & PRODUCTION PROBLEMS 🟠

## Problem 11 — Seed data runs in app

Audit says seed service is compiled into the production app and runs on launch, although guarded against overwriting existing documents. 

### Solution

Development:

```text
Seed allowed
```

Production:

```text
Seed completely disabled
```

Preferably separate development/staging/production environments.

---

## Problem 12 — Hardcoded development shortcuts

Current code reportedly contains:

* Admin phone
* Shopkeeper phone mapping
* Development identity assumptions
* Seed behavior

These should not survive production.

### Solution

Create a **production cleanup checklist** and verify every item before launch.

---

## Problem 13 — Debug logs expose internal information

Audit identifies `debugPrint` calls with Firestore paths and errors. 

### Solution

Development:

```text
Detailed logs
```

Production:

```text
User:
"Something went wrong"

Internal monitoring:
Actual error
```

Never expose:

* Secrets
* OTP
* Tokens
* Full sensitive user data
* Internal backend paths unnecessarily

---

# GROUP F — WHATSAPP OTP SECURITY 🔴

## Problem 14 — WhatsApp OTP directly from Flutter would be dangerous

Correct architecture is:

❌

```text
Flutter
↓
WhatsApp provider secret
```

because secret extraction could lead to provider abuse.

Correct:

```text
Flutter
↓
Your Backend
↓
Rate limits
↓
WhatsApp Provider
```



---

## Problem 15 — OTP bill exhaustion attack

Attacker ka goal account hack karna bhi nahi hoga.

Woh simply:

```text
Request OTP
Request OTP
Request OTP
Request OTP
```

karke tumhara bill badhane ki koshish kar sakta hai.

### Solution: Multi-layer protection

Recommended conceptual limits from audit:

```text
Same phone cooldown: 60 sec

Per phone:
3/hour
5/day

Per IP:
10/hour

OTP expiry:
5 min

Wrong attempts:
5

Then:
temporary lock

Global emergency cap:
adjustable

Cost alert:
before monthly threshold
```



**Important:** Ye numbers final fixed law nahi hain. Hum YummBU ke actual usage ke according tune karenge.

---

## Problem 16 — OTP user enumeration

Backend unnecessarily ye reveal nahi kare:

```text
"This phone number is registered"

vs

"This phone number is not registered"
```

because attacker phone numbers test karke existing accounts identify kar sakta hai. 

---

# GROUP G — ADMIN SECURITY 🔴

Admin compromise = highest impact.

Admin ke liye normal customer se stronger protection chahiye.

## Sensitive actions

* Delete shop
* Change role
* Assign shopkeeper
* Change security settings
* Delete important data

Recommended flow:

```text
Admin login
↓
Admin authorization
↓
Sensitive action?
↓
Additional verification if required
↓
Action
↓
Audit log
```

Audit trail:

```text
WHO
WHAT
WHEN
TARGET
RESULT
```



---

# GROUP H — SESSION & ACCOUNT RECOVERY

Current architecture has no real token/session/revocation model according to the audit. 

## Required

* Logout
* Token refresh
* Role change invalidation
* Access revocation
* Compromised account response

Example:

```text
Shopkeeper removed
↓
Role revoked
↓
Existing session invalidated
↓
Next protected request denied
```

---

# GROUP I — APP CHECK & ABUSE PROTECTION 🟠

App Check useful hai, but:

> **App Check ≠ Authentication**
>
> **App Check ≠ Authorization**

Correct model:

```text
App Check
+
Authentication
+
Firestore Rules
+
Backend authorization
+
Rate limiting
```



Isko hardening stage mein enable/test karke enforcement karna better hai.

---

# GROUP J — SECRETS & GITHUB

Audit reports `google-services.json` being committed to Git. 

Lekin yahan ek correction important hai:

**Firebase client configuration/API key ka repository mein hona automatically “database password leaked” nahi hota.** Firebase client config public architecture ka part ho sakta hai.

Actual danger mainly hota hai:

```text
Open Firestore rules
+
Open Storage rules
+
Weak authorization
```

Fir public project configuration attacker ko Firebase resources locate karne mein help kar sakta hai.

So fix:

* Check repo history
* Ensure real secrets were never committed
* Add sensitive files appropriately to ignore policy where applicable
* Rotate any genuinely private credentials if exposed
* Restrict API keys appropriately
* Never commit service accounts / provider secrets

---

# 🧠 Sabse bada contradiction jo mujhe documents mein mila

## Document 1 ka roadmap:

```text
Security first
↓
WhatsApp authentication last
```

## Document 2/3 ka conclusion:

```text
Authentication foundation pehle honi chahiye
```

### Mera final verdict:

**Dono baaton ko intelligently combine karna chahiye.**

Tum testing ke dauran real paid WhatsApp OTP implement nahi karna chahte — ye valid hai.

Lekin authorization architecture ko fake local identity ke around permanently build karna bhi galat hoga.

### Isliye best solution:

```text
PHASE 0
Security design
        ↓
PHASE 1
Firebase Auth architecture
+
Development/Test authentication
        ↓
PHASE 2
Roles + Firestore + Storage
        ↓
PHASE 3
Order backend security
        ↓
PHASE 4
Real WhatsApp OTP replace test auth
```

Yaani:

> **Real WhatsApp OTP later.**
>
> **But authentication-compatible architecture now.**

This is the best reconciliation of all three documents. 

---

# 🛡️ MY FINAL YUMMBU SECURITY ROADMAP

## PHASE 0 — SECURITY BLUEPRINT

### 0.1 Threat model

Exactly define:

* Customer
* Shopkeeper
* Admin
* Anonymous attacker
* Bot/spammer
* Competitor
* Compromised account

### 0.2 Trust boundaries

```text
Flutter = untrusted
Local storage = untrusted
Client values = untrusted

Firebase Rules + Backend = trusted enforcement
```

### 0.3 Authorization matrix

Exactly define every operation.

Example:

| Action           | Customer | Shopkeeper | Admin                |
| ---------------- | -------- | ---------- | -------------------- |
| Browse shop      | ✅        | ✅          | ✅                    |
| Read own order   | ✅        | ❌          | Authorized           |
| Read shop orders | ❌        | Own shop   | Authorized           |
| Edit menu        | ❌        | Own shop   | ✅                    |
| Delete shop      | ❌        | ❌          | Authorized           |
| Change role      | ❌        | ❌          | Trusted backend only |

### 0.4 Define sensitive fields

Example:

```text
customerId
shopId
price
totalAmount
role
assignedShop
status
createdAt
```

### 0.5 Define exact order state machine

### 0.6 Define privileged backend operations

---

# PHASE 1 — IDENTITY FOUNDATION

## 1.1 Add Firebase authentication-compatible architecture

Not necessarily paid WhatsApp OTP yet.

Use:

```text
Development/Test Identity
```

but structure it around:

```text
UID
↓
Identity
↓
Authorization
```

## 1.2 Remove client-controlled roles

## 1.3 Create role model

```text
Customer
Shopkeeper
Admin
```

## 1.4 Create shopkeeper → shop authorization

## 1.5 Session/logout/revocation architecture

---

# PHASE 2 — FIREBASE AUTHORIZATION

## 2.1 Lock Firestore with deny-by-default

## 2.2 Customer ownership rules

## 2.3 Shop isolation

## 2.4 Protect roles

## 2.5 Protect sensitive fields

## 2.6 Move ShopStats to trusted backend

## 2.7 Lock Storage

* Auth required
* Own shop only
* Type validation
* Size limit
* Delete protection

## 2.8 Add route guards

**Last**, because route guards are UI protection, not the main security wall.

---

# PHASE 3 — ORDER SECURITY

## 3.1 Server-authoritative order creation

## 3.2 Server price calculation

## 3.3 Validate item exists

## 3.4 Validate availability

## 3.5 Validate quantity

## 3.6 Validate correct shop

## 3.7 Enforce status transitions

## 3.8 Protect immutable fields

## 3.9 Duplicate/replay protection

## 3.10 Order spam limits

---

# PHASE 4 — REAL WHATSAPP OTP

Now replace development authentication.

```text
WhatsApp Number
↓
Backend
↓
Rate limit
↓
OTP
↓
Verify
↓
Firebase Auth
↓
UID
↓
Role
↓
Panel
```

### Include:

* OTP expiry
* Resend cooldown
* Phone limits
* Wrong attempt limits
* Temporary lockout
* Global emergency limit
* Cost monitoring
* Provider secret protection
* No account enumeration

---

# PHASE 5 — ABUSE & APP PROTECTION

## 5.1 Firebase App Check

## 5.2 Order spam protection

## 5.3 Backend/API rate limits

## 5.4 Storage abuse limits

## 5.5 Suspicious activity detection

## 5.6 Button double-submit protection

---

# PHASE 6 — ADMIN & SESSION HARDENING

## 6.1 Strong admin authorization

## 6.2 Sensitive action re-verification

## 6.3 Role change invalidation

## 6.4 Session revocation

## 6.5 Audit logs

## 6.6 Emergency account lockout

## 6.7 Future MFA if required

---

# PHASE 7 — PRODUCTION CLEANUP

This should happen before launch, not be forgotten at the end.

Checklist:

* Remove hardcoded phone logic
* Disable seed service
* Remove test accounts
* Remove bypasses
* Remove debug shortcuts
* Safe error messages
* Production logger
* Secret review
* Git history check
* API restrictions
* Environment separation
* Dependency audit
* Release build hardening

---

# PHASE 8 — MONITORING & RECOVERY

## Monitor only important events

* OTP spike
* Failed authentication
* Suspicious authorization attempts
* Admin actions
* Unusual order volume
* Backend failures

Avoid logging every:

```text
menu view
cart add
page navigation
```

## Recovery plan

```text
Attack detected
↓
Block/revoke access
↓
Inspect logs
↓
Rotate credentials if necessary
↓
Restore affected data
↓
Patch vulnerability
```

---

# PHASE 9 — FINAL ATTACK TESTING

Before public launch, test as an attacker.

### Customer vs Customer

* Can A read B's orders?
* Can A modify B's order?

### Customer vs Shopkeeper

* Can customer edit menu?
* Can customer upload images?

### Customer vs Admin

* Can customer access admin?
* Can customer change role?

### Shopkeeper A vs Shopkeeper B

* Can A read B's orders?
* Can A change B's price?
* Can A delete B's images?

### Order tests

* Price modification
* Total modification
* Quantity abuse
* Fake item
* Wrong shop
* Status manipulation
* Duplicate/replay order

### OTP tests

* Spam
* Guessing
* Resend abuse
* Global limit
* Session after revocation

### Direct backend tests

Ignore Flutter completely and test whether backend/Firebase itself rejects unauthorized operations.

This is exactly the mindset all three documents ultimately converge on. 

---

# 🏁 Final priority order

Agar mujhe YummBU ke liye **strictly one-by-one implementation order** choose karna ho, main ye choose karunga:

```text
1. Security Blueprint
        ↓
2. Identity Architecture
        ↓
3. Role + Shop Authorization
        ↓
4. Firestore Security
        ↓
5. Storage Security
        ↓
6. Route Guards
        ↓
7. Server-Side Order Creation
        ↓
8. Order State + Duplicate Protection
        ↓
9. Development Cleanup
        ↓
10. Real WhatsApp OTP
        ↓
11. OTP Cost/Abuse Protection
        ↓
12. App Check
        ↓
13. Admin Hardening
        ↓
14. Logging + Monitoring
        ↓
15. Backup + Recovery
        ↓
16. Full Attack Testing
        ↓
17. Public Launch
```

## My strongest recommendation

**Abhi directly Phase 1.1 coding start nahi karni chahiye.**

Pehle hum **Phase 0 ka ek proper “YummBU Security Blueprint”** banayenge:

* Exactly kaun kya kar sakta hai
* Kaun kya nahi kar sakta
* Kaunsa data public hai
* Kaunsa private hai
* Kaunsa data client kabhi control nahi karega
* Kaunsa action backend se hi hoga

Uske baad hum **Problem #1 se one-by-one implementation** start karenge. Isse hum teen alag roadmaps ke confusion ko hata kar ek single, clean, professional roadmap follow karenge.

# ⭐ Final YummBU Security Architecture

Ultimately architecture roughly aisa hoga:

```
```

```
                  YummBU
                     │
             ┌───────┴────────┐
             │                │
         Customer          Staff
             │          ┌─────┴─────┐
             │          │           │
          WhatsApp   Shopkeeper    Admin
             │
          OTP/Auth
             │
      Firebase Authentication
             │
       ┌─────┴──────┐
       │            │
   App Check     Role/Auth
       │            │
       └─────┬──────┘
             │
      Secure Backend
      / Cloud Functions
             │
      ┌──────┴─────────┐
      │                │
   Firestore         Storage
      │                │
      └──────┬─────────┘
             │
       Security Rules
             │
       Abuse Protection
             │
       Logging/Monitoring
             │
       Incident Recovery
```

authentication sare roles k liye ek jesa hoga

Haan — **bilkul. Authentication ka basic login flow Customer, Shopkeeper aur Admin, teeno ke liye same hoga.** Tumhara final model ye hona chahiye:

```text
                    YummBU APP
                        │
                        ▼
              Enter WhatsApp Number
                        │
                        ▼
                 Request OTP
                        │
                        ▼
              Verify WhatsApp OTP
                        │
                        ▼
            Firebase Authentication
                        │
                        ▼
                 Unique User ID
                        │
                        ▼
              System checks authorization
                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
       Customer     Shopkeeper       Admin
          │             │             │
          ▼             ▼             ▼
        Home       Shopkeeper Panel  Admin Panel
```

## Important difference: Authentication vs Role

### Authentication — sabke liye same

Teeno users:

* Customer
* Shopkeeper
* Admin

sab yehi flow follow karenge:

```text
WhatsApp Number
      ↓
WhatsApp OTP
      ↓
OTP Verified
      ↓
Firebase Authentication
      ↓
Logged In
```

Yahan system sirf ye verify karta hai:

> **"Haan, ye person genuinely iss WhatsApp number ko control karta hai."**

---

### Role / Authorization — authentication ke baad different

OTP verify hone ke baad system check karega:

```text
Is authenticated user ka role kya hai?
```

Phir:

```text
ROLE = customer
        ↓
      Home


ROLE = shopkeeper
        ↓
 Shopkeeper Panel


ROLE = admin
        ↓
    Admin Panel
```

## Final simple architecture

```text
                    USER
                      │
                      ▼
              WhatsApp Number
                      │
                      ▼
                 WhatsApp OTP
                      │
                      ▼
              SAME AUTH FOR ALL
                      │
                      ▼
           Firebase Auth / User UID
                      │
                      ▼
            ROLE + ACCESS CHECK
                      │
          ┌───────────┼───────────┐
          │           │           │
          ▼           ▼           ▼
       CUSTOMER   SHOPKEEPER    ADMIN
          │           │           │
          ▼           ▼           ▼
        HOME       OWN SHOP      GOD MODE
```

### Ek important security rule

**OTP successful hone ka matlab automatically Admin ya Shopkeeper banna nahi hai.**

Example:

```text
Attacker enters own WhatsApp number
        ↓
OTP verify successfully
        ↓
Authenticated successfully ✅
        ↓
System checks role
        ↓
Not assigned as Admin/Shopkeeper
        ↓
Customer access only
```

Isliye attacker apna valid OTP verify karke bhi admin nahi ban sakta.

### Shopkeeper ke case mein extra check

```text
OTP verified
     ↓
Firebase UID
     ↓
Role = shopkeeper?
     ↓
YES
     ↓
Assigned Shop IDs check
     ↓
Only those shops accessible
```

So final principle:

> **Authentication same for everyone. Access different according to role.**

Aur main architecture diagram mein `Customer → WhatsApp OTP/Auth` aur `Staff` ko alag dikhane ke bajaye isko update karna chahiye, kyunki **Admin aur Shopkeeper bhi exactly same WhatsApp OTP authentication use karenge**.

# 🛡️ YummBU — FINAL SECURITY STRUCTURE & BUILD PLAN

Perfect. Ab hum alag-alag ideas, random security features aur changing roadmaps ko side mein rakhte hain.

**Ye hamara final master structure hoga.**
Hum isi order ko follow karenge aur **ek phase complete + test + verify** karne ke baad hi next phase par jayenge.

Simple language mein:

> **Pehle system ko pata chalega user kaun hai → phir system decide karega usko kya access milega → phir database secure hoga → phir orders secure honge → phir OTP aur spam protection → phir monitoring aur final attack testing.**

---

# 🏗️ 1. YummBU ka Final Security Architecture

Sabhi roles ke liye **same authentication**:

```text
                         YUMMBU
                            │
                            ▼
                    Enter WhatsApp Number
                            │
                            ▼
                      Request OTP
                            │
                            ▼
                    Secure OTP Backend
                            │
                     ┌──────┴──────┐
                     │             │
              Abuse Check      Rate Limits
                     │             │
                     └──────┬──────┘
                            │
                            ▼
                     WhatsApp OTP
                            │
                            ▼
                      Verify OTP
                            │
                            ▼
                  Firebase Authentication
                            │
                            ▼
                     UNIQUE USER UID
                            │
                            ▼
                   ROLE / ACCESS CHECK
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
       CUSTOMER         SHOPKEEPER          ADMIN
          │                 │                 │
          ▼                 ▼                 ▼
        HOME           OWN SHOP PANEL     ADMIN PANEL
          │                 │                 │
          └─────────────────┼─────────────────┘
                            │
                            ▼
                     SECURE BACKEND
                    Cloud Functions/API
                            │
              ┌─────────────┼──────────────┐
              │             │              │
              ▼             ▼              ▼
          FIRESTORE      STORAGE       AUDIT LOGS
              │             │              │
              └─────────────┼──────────────┘
                            │
                            ▼
                      SECURITY RULES
                            │
                            ▼
                    APP CHECK + LIMITS
                            │
                            ▼
                 MONITORING & DETECTION
                            │
                            ▼
                   INCIDENT / RECOVERY
```

---

# 🧠 2. Sabse Important Rule

YummBU mein **Flutter app ko trusted nahi maana jayega**.

Matlab:

```text
Flutter App
❌ Security authority nahi
❌ Final price authority nahi
❌ Role authority nahi
❌ Admin authority nahi
❌ Order status authority nahi
```

Flutter ka kaam mainly:

```text
User ko UI dikhana
↓
User input lena
↓
Request bhejna
↓
Result dikhana
```

Actual security enforcement:

```text
Firebase Authentication
+
Authorization
+
Firestore Rules
+
Storage Rules
+
Cloud Functions / Backend
```

---

# 👥 3. YummBU ke 3 Main Roles

## 👨‍🎓 Customer

Customer kar sakta hai:

* Shops dekhna
* Menus dekhna
* Items search karna
* Cart mein add karna
* Order place karna
* Apne orders dekhna
* Allowed state mein order cancel karna
* Reorder karna

Customer nahi kar sakta:

```text
Admin panel access ❌
Shopkeeper panel access ❌
Menu price edit ❌
Shop create/delete ❌
Other customer orders dekhna ❌
Order total manipulate ❌
Order status delivered karna ❌
Role change karna ❌
```

---

## 🏪 Shopkeeper

Shopkeeper kar sakta hai:

* Apni assigned shop access
* Apna menu manage
* Apne item ki availability change
* Apne orders dekhna
* Order accept/reject
* Accepted order delivered mark karna

Shopkeeper nahi kar sakta:

```text
Dusri shop access ❌
Dusri shop ke orders dekhna ❌
Dusri shop ka menu edit ❌
Khud ko admin banana ❌
Role change karna ❌
Customer ka order manipulate karna outside allowed actions ❌
```

Important:

```text
Shopkeeper ≠ All Shops Access
```

Actual system:

```text
Shopkeeper UID
        +
Assigned Shop ID(s)
        =
Allowed Shop Access
```

---

## 👑 Admin

Admin authorized management kar sakta hai:

* Shop add/edit/delete
* Shopkeeper assign/remove
* Important data manage
* Security-related administrative actions
* Suspicious access handle
* Access revoke

Lekin admin access bhi sirf Flutter route se secure nahi hoga.

```text
/admin route
      ↓
Role check
      ↓
Backend / Firestore authorization
```

---

# 🔐 4. Authentication aur Authorization ka Difference

## Authentication

Question:

> **"Tum kaun ho?"**

Sabke liye same:

```text
WhatsApp Number
        ↓
OTP
        ↓
Verified
        ↓
Firebase UID
```

---

## Authorization

Question:

> **"Tum kya kar sakte ho?"**

```text
UID
 ↓
Role Check
 ↓
Customer?
Shopkeeper?
Admin?
 ↓
Allowed permissions
```

Example:

```text
Rajat enters OTP
        ↓
Number verified
        ↓
Firebase UID
        ↓
System checks role
        ↓
Admin
        ↓
Admin access
```

Koi attacker apna OTP successfully verify kar le:

```text
Attacker
 ↓
Valid OTP verified ✅
 ↓
Authenticated ✅
 ↓
Role check
 ↓
Customer
 ↓
Only customer access
```

**Valid OTP ≠ Admin access.**

---

# 🗂️ 5. Data Classification

Hum pehle hi decide karenge ki kaunsa data kitna sensitive hai.

## 🟢 Public Data

Normally public:

* Shop name
* Shop description
* Menu
* Item name
* Item price
* Item image
* Opening hours
* Shop availability

---

## 🟡 Private User Data

Protected:

* User phone number
* User identity
* Personal order history
* Current orders
* Special instructions

---

## 🔴 Sensitive System Data

Highly protected:

* Roles
* Admin assignment
* Shopkeeper assignment
* Authentication tokens
* WhatsApp provider secrets
* Backend secrets
* Service accounts
* Audit logs
* Security settings

---

# 🔥 6. Final Order Security Architecture

Order ke time Flutter final authority nahi hoga.

## Flutter sirf bhejega:

```text
shopId
itemId
quantity
specialInstructions
```

## Flutter blindly trusted nahi hoga for:

```text
Price ❌
Total amount ❌
Discount ❌
Final status ❌
```

---

## Actual order flow

```text
CUSTOMER
    ↓
Select Items
    ↓
Flutter sends request
    ↓
SECURE BACKEND
    ↓
Check authenticated user
    ↓
Check shop exists
    ↓
Check shop active/open
    ↓
Fetch actual menu item
    ↓
Check item available
    ↓
Validate quantity
    ↓
Fetch real price
    ↓
Calculate real total
    ↓
Create order
    ↓
status = PLACED
```

---

# 🔄 7. Final Order Lifecycle

```text
                    PLACED
                  /    |    \
                 /     |     \
                ▼      ▼      ▼
           ACCEPTED REJECTED CANCELLED
               │
               ▼
           DELIVERED
```

Allowed:

```text
Placed → Accepted
Placed → Rejected
Placed → Cancelled
Accepted → Delivered
```

Blocked:

```text
Delivered → Cancelled ❌
Rejected → Accepted ❌
Cancelled → Accepted ❌
Delivered → Placed ❌
```

Har transition check karega:

```text
Current status
+
User role
+
Order ownership
+
Requested new status
```

---

# 🧱 8. FINAL BUILD ROADMAP

Ab ye hamara actual implementation order hoga.

---

# 🟦 PHASE 0 — SECURITY BLUEPRINT

**Is phase mein code change minimum hoga. Pehle exact rules decide honge.**

## 0.1 Threat Model

Hum identify karenge:

```text
Customer
Shopkeeper
Admin
Curious student
Malicious customer
Competitor
Bot
OTP spammer
External attacker
Compromised account
```

## 0.2 Trust Boundaries

Final rule:

```text
Client = Untrusted
Local Storage = Untrusted
Client-side Role = Untrusted
Client-side Price = Untrusted
Client-side Total = Untrusted
```

Trusted enforcement:

```text
Firebase Auth
Cloud Functions
Firestore Rules
Storage Rules
```

## 0.3 Permission Matrix

Har action ka answer:

| Action           | Customer     | Shopkeeper | Admin      | Backend      |
| ---------------- | ------------ | ---------- | ---------- | ------------ |
| View shops       | ✅            | ✅          | ✅          | —            |
| View own order   | ✅            | ❌          | Authorized | —            |
| View shop orders | ❌            | Own shop   | Authorized | —            |
| Edit menu        | ❌            | Own shop   | ✅          | —            |
| Create order     | Request only | ❌          | —          | ✅            |
| Calculate total  | Display      | ❌          | —          | ✅            |
| Change role      | ❌            | ❌          | Controlled | Trusted only |
| Delete shop      | ❌            | ❌          | Authorized | —            |

## 0.4 Sensitive Field Map

We define fields which user cannot manipulate:

```text
role
customerId
shopId
totalAmount
price
createdAt
status
assignedShopId
```

### Phase 0 complete when:

* Threat model final
* Permission matrix final
* Sensitive fields final
* Order lifecycle final

---

# 🟦 PHASE 1 — IDENTITY FOUNDATION

## 1.1 Firebase Authentication Architecture

Abhi real WhatsApp OTP mandatory nahi.

Testing mode:

```text
Test Identity
↓
Firebase-compatible authentication flow
↓
Real UID
```

Production mein same structure:

```text
WhatsApp OTP
↓
Firebase Auth
↓
UID
```

## 1.2 UID-Based Identity

Phone number ya local storage se identity nahi.

```text
Firebase UID = Real identity reference
```

## 1.3 Role System

```text
Customer
Shopkeeper
Admin
```

Role client khud change nahi kar sakta.

## 1.4 Shop Assignment

```text
Shopkeeper A
      ↓
Assigned Shop A
      ↓
Only Shop A access
```

## 1.5 Session Foundation

* Login
* Logout
* Token refresh
* Access revoked handling

### Phase 1 complete when:

```text
Every user has UID
+
Every protected user has correct role
+
Shopkeeper has controlled shop assignment
```

---

# 🟦 PHASE 2 — FIRESTORE SECURITY

## 2.1 Default Deny

Starting principle:

```text
Nobody gets write access automatically.
```

Har permission explicitly allow hogi.

## 2.2 Customer Security

Customer:

```text
Own order read ✅
Other order read ❌
Own allowed cancellation ✅
Price update ❌
Status abuse ❌
```

## 2.3 Shopkeeper Isolation

```text
Shopkeeper A
    ↓
Shop A data ✅

Shop B data ❌
```

## 2.4 Admin Authorization

Sensitive access backend/rules se verify hoga.

## 2.5 Sensitive Fields Protection

User update nahi kar sakta:

```text
customerId
shopId
role
price
totalAmount
createdAt
```

unless trusted server operation explicitly kare.

## 2.6 ShopStats Protection

Stats:

```text
Orders
Revenue
Counts
```

normal client directly manipulate nahi karega.

Trusted backend update karega.

### Phase 2 complete when:

Direct Firebase attack test:

```text
Customer → Other order ❌
Customer → Admin data ❌
Shopkeeper A → Shop B ❌
Random user → menu write ❌
```

---

# 🟦 PHASE 3 — STORAGE SECURITY

## 3.1 Public Image Reading

Users shop/menu images dekh sakte hain.

## 3.2 Controlled Upload

Only:

```text
Authorized Shopkeeper
Authorized Admin
```

## 3.3 File Validation

Allow:

```text
JPEG
PNG
WebP
```

Block:

```text
EXE ❌
APK ❌
ZIP ❌
Random binary ❌
Huge files ❌
```

## 3.4 Ownership Validation

```text
Shopkeeper A
→ Shop A folder only
```

### Phase 3 complete when:

Unauthorized upload/delete test fail kare.

---

# 🟦 PHASE 4 — ROUTE & CLIENT PROTECTION

## 4.1 Route Guards

```text
Customer → /home
Shopkeeper → /shopkeeper
Admin → /admin
```

Wrong route:

```text
/admin
↓
Role check
↓
Denied
↓
Safe redirect
```

## 4.2 UI Permission Checks

Buttons bhi hide/disable honge where necessary.

But remember:

```text
UI protection ≠ actual security
```

Actual security Phase 2 mein backend/database enforce karega.

## 4.3 Local Storage Cleanup

Local storage:

```text
Theme
Cache
Non-sensitive preferences
```

ke liye.

Not:

```text
Admin authority ❌
Shopkeeper authority ❌
Security authority ❌
```

---

# 🟦 PHASE 5 — SERVER-SIDE ORDER SECURITY

## 5.1 Secure Order Creation

Client direct authoritative order create nahi karega.

## 5.2 Real Price Fetch

Backend Firestore se current price lega.

## 5.3 Availability Check

Out-of-stock item order nahi.

## 5.4 Quantity Validation

Invalid quantity:

```text
0 ❌
Negative ❌
Unreasonable huge number ❌
```

## 5.5 Canonical Total

Backend:

```text
Real price × validated quantity
```

## 5.6 Duplicate Protection

Double click:

```text
Place Order
Place Order
Place Order
```

= duplicate orders nahi.

## 5.7 Spam Limits

Normal usage allowed.

Suspicious repeated orders restricted.

### Phase 5 complete when:

Modified client bhi ₹1 total force na kar sake.

---

# 🟦 PHASE 6 — ORDER LIFECYCLE SECURITY

## Customer

Only:

```text
Placed → Cancelled
```

and only own order.

## Shopkeeper

Only:

```text
Placed → Accepted
Placed → Rejected
Accepted → Delivered
```

and only own shop's order.

## Admin

Authorized exceptional access only.

### Phase 6 complete when:

Har invalid transition backend/database reject kare.

---

# 🟦 PHASE 7 — REAL WHATSAPP OTP

**Yahan real production authentication activate hoga.**

Same flow for:

```text
Customer
Shopkeeper
Admin
```

```text
Enter WhatsApp Number
        ↓
Request OTP
        ↓
Backend checks limits
        ↓
WhatsApp Provider
        ↓
OTP delivered
        ↓
User enters OTP
        ↓
Backend verifies
        ↓
Firebase identity
        ↓
UID
        ↓
Role check
```

---

# 🟦 PHASE 8 — OTP ABUSE & COST PROTECTION

Ye tumhare liye especially important hai.

## Layer 1 — Resend Cooldown

```text
OTP sent
↓
Wait
↓
Resend allowed
```

## Layer 2 — Per Number Limit

Ek number unlimited OTP nahi manga sakta.

## Layer 3 — Wrong OTP Limit

Repeated guessing:

```text
Wrong
Wrong
Wrong
↓
Temporary restriction
```

## Layer 4 — IP/Request Limits

One source se massive spam restrict.

## Layer 5 — App/Device Protection

Firebase App Check.

## Layer 6 — Global Emergency Cap

```text
Normal OTP usage
        ↓
Sudden attack spike
        ↓
Emergency protection
        ↓
Alert
```

### Important principle

Exact limits abhi hardcode nahi karenge.

Pehle real usage samjhenge, then tune karenge.

---

# 🟦 PHASE 9 — APP CHECK & AUTOMATED ABUSE

Firebase App Check helps verify ki request expected app environment se aa rahi hai.

Protection targets:

* Automated scripts
* Unauthorized clients
* Basic API abuse

But:

```text
App Check
≠
Authentication
≠
Authorization
```

Teeno separate layers hain.

---

# 🟦 PHASE 10 — ADMIN HARDENING

Admin = highest impact.

## Protection:

* Strong role verification
* Sensitive action logging
* Session revocation
* Suspicious activity handling
* Optional extra verification for critical actions

Sensitive actions:

```text
Delete shop
Change role
Assign shopkeeper
Security configuration change
```

Flow:

```text
Admin
↓
Sensitive action
↓
Extra verification if required
↓
Action
↓
Audit log
```

---

# 🟦 PHASE 11 — ERROR SECURITY & LOGGING

## User sees:

```text
Something went wrong.
Please try again.
```

## Internal system stores useful details.

Never expose:

```text
Raw Firebase exception
Stack trace
Secret
Token
Internal credentials
```

Important logs:

```text
Role changes
Admin actions
Access revoked
Repeated OTP failures
Suspicious requests
Order security failures
```

Avoid unnecessary logs:

```text
Every menu view ❌
Every cart add ❌
Every page navigation ❌
```

---

# 🟦 PHASE 12 — PRODUCTION CLEANUP

Before launch:

```text
Remove hardcoded admin numbers
Remove test accounts
Disable seed services
Remove auth bypass
Remove debug shortcuts
Check logs
Check secrets
Check Git history
Check environment configs
Review dependencies
```

Separate:

```text
Development
Testing/Staging
Production
```

Production must not accidentally use development shortcuts.

---

# 🟦 PHASE 13 — MONITORING & INCIDENT RESPONSE

## Monitor:

```text
OTP spikes
Failed authentication spikes
Unauthorized access attempts
Order spikes
Backend errors
Storage abuse
Suspicious admin activity
```

## Response:

```text
DETECT
  ↓
CONFIRM
  ↓
LIMIT / BLOCK
  ↓
REVOKE ACCESS
  ↓
INVESTIGATE
  ↓
FIX
  ↓
RESTORE IF REQUIRED
  ↓
DOCUMENT
```

---

# 🟦 PHASE 14 — BACKUP & RECOVERY

Security ka matlab sirf attack rokna nahi.

Agar:

```text
Data accidentally deleted
Shop deleted wrongly
Admin mistake
Bad deployment
Security incident
```

To recovery plan hona chahiye.

We will define:

* What data needs backup
* Recovery procedure
* Access control for backups
* Restore testing

---

# 🟦 PHASE 15 — FINAL ATTACK TESTING

Public launch se pehle hum app ko normal user ki tarah nahi, **attacker ki tarah test karenge**.

## Customer attacks

```text
Other user's order access?
Price change?
Quantity manipulation?
Status manipulation?
Duplicate orders?
```

## Shopkeeper attacks

```text
Shop B access?
Shop B menu edit?
Shop B orders?
Role escalation?
```

## Admin attacks

```text
Direct route?
Fake role?
Modified client?
Old session after revocation?
```

## OTP attacks

```text
Rapid resend?
Wrong OTP guessing?
Automated spam?
Cost limit?
```

## Firebase attacks

```text
Direct Firestore request?
Direct Storage upload?
Direct delete?
Unauthorized read?
Unauthorized write?
```

---

# 🏁 FINAL BUILD ORDER — THIS IS THE ONE WE STICK TO

```text
PHASE 0
Security Blueprint
        ↓
PHASE 1
Identity Foundation
        ↓
PHASE 2
Firestore Security
        ↓
PHASE 3
Storage Security
        ↓
PHASE 4
Route & Client Protection
        ↓
PHASE 5
Server-Side Order Security
        ↓
PHASE 6
Order Lifecycle Security
        ↓
PHASE 7
Real WhatsApp OTP
        ↓
PHASE 8
OTP Abuse & Cost Protection
        ↓
PHASE 9
App Check & Automated Abuse Protection
        ↓
PHASE 10
Admin Hardening
        ↓
PHASE 11
Error Security & Logging
        ↓
PHASE 12
Production Cleanup
        ↓
PHASE 13
Monitoring & Incident Response
        ↓
PHASE 14
Backup & Recovery
        ↓
PHASE 15
Final Attack Testing
        ↓
PUBLIC LAUNCH 🚀
```

# 🎯 Hamara Working Rule From Now On

Har phase ke liye hum ye 5 steps follow karenge:

```text
1. Current problem samjhenge
        ↓
2. Desired behavior define karenge
        ↓
3. Attack scenarios dekhenge
        ↓
4. Antigravity/implementation tool ko detailed task denge
        ↓
5. Test + verify karke phase lock karenge
```

Aur **kisi bhi phase mein unnecessary redesign nahi hoga**. Existing YummBU UI/functionality ko preserve karte hue security layer build hogi.

## Final principle

> **Authentication sabke liye same hogi. Authorization sabke liye different hogi. Flutter UI convenience ke liye hai. Actual security backend, Firebase Auth, Firestore Rules, Storage Rules aur controlled server-side operations enforce karenge.**

**Ye ab hamara final YummBU Security Plan hai. Isi ko base maan kar ab hum Phase 0 se systematically build start kar sakte hain.** 🔐🚀


Haan. Maine jo **Claude ka complete pre-security audit** diya hai, usko YummBU ke existing architecture aur hamare pehle finalized security plan ke context mein carefully read kar liya.

Is audit ke basis par **Checkpoint 7 ko blindly implement nahi karna hai**. Pehle security architecture ko final lock karenge, phir ek-ek layer implement/test karenge.

### Sabse important conclusion

YummBU ka current functional system largely ready hai. Security side par main problem ye hai:

> **Abhi identity client-side hai; production mein identity Firebase Auth se aayegi, aur authorization backend/rules enforce karenge.**

Final authentication flow:

```text
                    YummBU APP
                         │
                         ▼
                Enter WhatsApp Number
                         │
                         ▼
                  WhatsApp OTP
                         │
                         ▼
                 OTP Verification
                         │
                         ▼
              Firebase Auth Identity
                         │
                    Firebase UID
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
        Authentication        Authorization
        "Who are you?"         "What can you do?"
              │                     │
              └──────────┬──────────┘
                         ▼
                 Role Determination
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
      CUSTOMER       SHOPKEEPER       ADMIN
          │              │              │
          ▼              ▼              ▼
       Customer       Shop Panel      Admin Panel
                         │
                    shopId binding
```

**Important:** WhatsApp OTP ko Firebase Auth ke saath integrate karne ka exact mechanism implementation stage par verify karna hoga; Firebase ka native phone-auth flow traditionally SMS-based hota hai. Agar WhatsApp OTP provider use karte hain, backend ko verified WhatsApp identity ko Firebase Auth identity se securely bind karna padega. Is part ko assumption par code nahi karenge.

---

# 🔐 FINAL YummBU SECURITY ROADMAP

## PHASE 0 — SECURITY FOUNDATION & FREEZE

### 0.1 Security baseline

* Existing code ka backup
* Git checkpoint/tag
* Current production-like build preserve
* Security changes isolated
* UI/UX **change nahi karna**
* Existing order workflow unnecessarily modify nahi karna

### 0.2 Secrets audit

Check:

* WhatsApp credentials
* Firebase service accounts
* private keys
* API secrets
* `.env`
* keystore
* Git history
* Cloud Function credentials

### 0.3 Environment separation

```text
Development
     ↓
Testing
     ↓
Production
```

Test credentials aur production credentials mix nahi honge.

---

# PHASE 1 — IDENTITY / AUTHENTICATION

## 1.1 Firebase Authentication

Current:

```text
SharedPreferences
   ↓
userPhone
   ↓
role
```

Replace with:

```text
WhatsApp verification
        ↓
Firebase Auth
        ↓
Firebase UID
```

**UID primary identity hoga.**

Phone number identity ka supporting attribute hoga.

---

## 1.2 WhatsApp OTP

Required protections:

### Per-phone

```text
60 sec cooldown
↓
limited OTP requests
↓
temporary lock
```

### OTP

```text
5 minute expiry
3–5 incorrect attempts
↓
OTP invalid
```

### Per-IP/device protection

Suspicious repeated requests ko throttle karna.

### Global protection

```text
OTP traffic spike
      ↓
circuit breaker
      ↓
WhatsApp API protected
      ↓
admin alert
```

Exact limits implementation/testing ke baad tune karenge; arbitrary limits ko blindly production mein lock nahi karenge.

---

## 1.3 Account creation

Successful verification ke baad:

```text
Firebase UID
WhatsApp number
createdAt
account status
```

User document create/update hoga.

---

# PHASE 2 — ROLE & AUTHORIZATION

Authentication aur authorization **alag concepts** rahenge.

### Authentication

> Tum kaun ho?

### Authorization

> Tum kya kar sakte ho?

---

## 2.1 Roles

```text
CUSTOMER
SHOPKEEPER
ADMIN
```

---

## 2.2 Customer

Customer:

```text
Firebase UID
       ↓
Customer account
       ↓
Customer data
       ↓
Own orders
```

Customer kabhi:

* Admin nahi ban sakta
* Shopkeeper nahi ban sakta
* doosre customer's order nahi dekh sakta

---

## 2.3 Shopkeeper

Shopkeeper identity:

```text
Firebase UID
      +
role = shopkeeper
      +
shopId = assigned shop
```

Example:

```text
UID: xyz123
role: shopkeeper
shopId: shop_01
```

Therefore:

```text
Shopkeeper A
    ↓
shop_01 only
```

Cannot access:

```text
shop_02
shop_03
admin
```

---

## 2.4 Admin

Admin authorization:

```text
Firebase Auth
      ↓
verified identity
      ↓
admin authorization
```

**Hardcoded admin phone number ko security mechanism nahi rakhenge.**

Client-side:

```dart
if (phone == adminPhone)
```

❌ Security nahi.

Backend:

```text
Firebase token
      ↓
admin authorization
```

✅ Security.

---

# PHASE 3 — FIRESTORE SECURITY

Ye YummBU ke **sabse important security phases** mein se ek hai.

## 3.1 Remove development bypass

Current:

```text
request.auth == null
```

wali temporary access conditions completely remove.

Production mein:

```text
Unauthenticated
       ↓
DENIED
```

---

# 3.2 Shops

Public users ko:

```text
shops
categories
menuItems
```

ka required read access milega.

But writes:

```text
Admin
    ↓
allowed

Shopkeeper
    ↓
only own shop
```

---

# 3.3 Orders

Current major risk:

```text
Any user → read orders
```

Replace:

```text
Customer
   ↓
only own orders

Shopkeeper
   ↓
only own shop orders

Admin
   ↓
authorized administrative access
```

---

# PHASE 4 — ORDER SECURITY

Ye financial/business security hai.

## 4.1 Client price = NEVER trusted

Client:

```text
shopId
itemId
quantity
choices
```

bhejega.

Client ye nahi decide karega:

```text
finalPrice
subtotal
totalAmount
discount
```

---

## 4.2 Server-side calculation

```text
Customer
   ↓
Cloud Function
   ↓
Fetch live menu
   ↓
Validate item
   ↓
Validate availability
   ↓
Fetch actual price
   ↓
Calculate total
   ↓
Create order
```

---

## 4.3 Negative/invalid values

Reject:

```text
quantity <= 0
negative price
negative total
invalid item
invalid shop
invalid modifier
```

---

# PHASE 5 — ORDER STATE MACHINE SECURITY

Final allowed flow:

```text
             ┌──────────────┐
             │    PLACED    │
             └──────┬───────┘
                    │
          ┌─────────┼──────────┐
          ▼         ▼          ▼
      ACCEPTED   REJECTED   CANCELLED
          │
          ▼
      DELIVERED
```

Customer:

```text
PLACED → CANCELLED
```

only before acceptance.

Shopkeeper:

```text
PLACED → ACCEPTED
PLACED → REJECTED

ACCEPTED → DELIVERED
```

No arbitrary transitions.

---

## Race-condition protection

Existing transaction-based protection already strong hai.

Maintain:

```text
Customer Cancel
        ↕
Shopkeeper Accept
        ↓
Atomic Firestore transaction
```

So dono simultaneously aaye toh invalid state nahi banega.

---

# PHASE 6 — CROSS-SHOP / IDOR PROTECTION

Attacker:

```text
shopId = victim_shop
```

change karke doosre shop ka data access na kar sake.

Backend checks:

```text
token.shopId == requested.shopId
```

Admin exception:

```text
role == admin
```

---

# PHASE 7 — FIREBASE STORAGE SECURITY

Current dangerous permission:

```text
unauthenticated delete
```

❌ Remove.

---

## Image upload

Only:

```text
Admin
Shopkeeper
```

with appropriate shop authorization.

Validate:

```text
Content-Type
File size
File path
User role
Shop ownership
```

Example:

```text
image/jpeg
image/png
image/webp
```

Executable/file upload:

```text
❌
```

---

# PHASE 8 — APP CHECK

YummBU ke liye important.

```text
Official YummBU App
       ↓
Firebase App Check
       ↓
Firebase services
```

Android:

```text
Play Integrity
```

Web/testing environment ke liye appropriate App Check provider.

Purpose:

```text
modified client
bots
scripts
unauthorized automated requests
```

ko reduce/block karna.

**Important:** App Check authorization ka replacement nahi hai.

It is an additional layer.

---

# PHASE 9 — OTP / ABUSE / SPAM PROTECTION

Ye especially important hai because WhatsApp OTP ka **real monetary cost** ho sakta hai.

### Layer 1

Per-phone cooldown.

### Layer 2

Per-phone hourly/daily limit.

### Layer 3

Per-IP throttling.

### Layer 4

Device/App Check validation.

### Layer 5

Wrong OTP attempt limit.

### Layer 6

Global circuit breaker.

### Layer 7

Monitoring + alert.

Architecture:

```text
OTP Request
     │
     ▼
App Check
     │
     ▼
IP Rate Limit
     │
     ▼
Phone Rate Limit
     │
     ▼
OTP Abuse Check
     │
     ▼
Global Safety Limit
     │
     ▼
WhatsApp Provider
```

---

# PHASE 10 — ORDER SPAM PROTECTION

Malicious student:

```text
100 fake orders
in 1 minute
```

nahi kar paye.

Possible controls:

```text
pending order limit
rapid-order cooldown
per-user rate limit
per-device abuse detection
server-side validation
```

Example concept:

```text
Customer
   ↓
Too many pending orders?
   ↓
YES → reject/throttle
NO  → continue
```

Exact threshold business testing ke baad finalize hoga.

---

# PHASE 11 — DEVICE TOKEN SECURITY

Current risk:

```text
any device
   ↓
write device token
   ↓
role = admin
```

❌

New model:

```text
Authenticated UID
       ↓
device token
       ↓
UID binding
       ↓
server-controlled role
```

User apna token register/update kar sakega.

Role arbitrary nahi set kar sakega.

---

# PHASE 12 — SESSION SECURITY

LocalStorage:

```text
user_role
user_phone
shop_id
```

ko **authorization source** nahi banayenge.

Local storage sirf:

```text
UI state
preferences
cache
```

ke liye.

Actual security:

```text
Firebase Auth
+
ID token
+
Custom Claims / server authorization
```

---

## Logout

```text
Logout
 ↓
Firebase signOut
 ↓
local sensitive state clear
```

---

## Access revoke

Suppose shopkeeper remove kiya:

```text
Admin
 ↓
remove shopkeeper authorization
 ↓
revoke/invalidate session as appropriate
 ↓
shopkeeper loses access
```

---

# PHASE 13 — ERROR SECURITY

User ko:

❌

```text
FirebaseException
permission-denied
internal stack trace
Cloud Function error details
```

nahi dikhana.

Instead:

```text
Something went wrong.
Please try again.
```

Backend logs mein technical details.

---

# PHASE 14 — LOGGING & AUDIT TRAIL

Important security actions:

```text
Admin shop created
Admin shop deleted
Shopkeeper assigned
Shopkeeper removed
Role changed
Suspicious OTP activity
Failed authorization
Suspicious order attempts
Security rule denial patterns
```

log honge.

But:

```text
every menu view
every image view
every normal browse
```

log nahi karenge.

Reason:

**security + cost balance.**

---

# PHASE 15 — ADMIN PROTECTION

Admin compromise ka impact highest hai.

Admin ke liye:

```text
Strong authentication
+
role authorization
+
App Check
+
sensitive-action validation
+
audit logs
+
session revocation
```

Future optional layer:

```text
Admin MFA / secondary verification
```

Normal customers ke liye unnecessary complexity nahi.

---

# PHASE 16 — DATA PRIVACY

Customer information:

```text
phone
name
orders
support queries
```

sirf required users ko accessible.

Shopkeeper:

```text
own operational data
```

Admin:

```text
authorized business data
```

Customer A:

```text
❌ Customer B data
```

---

# PHASE 17 — COST / RESOURCE ABUSE

Security sirf "hack" rokna nahi hai.

Attacker Firebase bill bhi increase kar sakta hai.

Protect:

```text
Firestore reads
Firestore writes
Storage uploads
Storage downloads
Cloud Functions
OTP messages
FCM abuse
```

Use:

```text
query limits
pagination
rate limits
App Check
server validation
storage limits
monitoring
```

---

# PHASE 18 — CLOUD FUNCTIONS SECURITY

Functions ko:

```text
Public blindly callable
```

nahi chhodna.

Every sensitive callable function:

```text
Authentication
+
App Check where appropriate
+
Authorization
+
Input validation
+
Rate limiting
```

---

# PHASE 19 — SERVER-SIDE ORDER EXPIRATION

Current audit ka ek genuine gap:

Client ticker par expiration depend karta hai.

Better:

```text
Cloud Scheduler
      ↓
Scheduled Cloud Function
      ↓
Find expired orders
      ↓
Validate state
      ↓
Expire safely
```

Isse:

```text
Customer app closed
Shopkeeper app closed
```

hone par bhi system correct rahega.

---

# PHASE 20 — SECURITY RULE TESTING

Sirf Dart unit tests enough nahi.

Actual:

```text
Firebase Emulator
      ↓
Firestore Rules
      ↓
Storage Rules
      ↓
Auth scenarios
```

test karenge.

Test cases:

### Customer

* own order read ✅
* another order read ❌
* own cancellation valid ✅
* accepted order cancellation ❌
* shop modification ❌
* admin access ❌

### Shopkeeper

* own shop access ✅
* other shop access ❌
* own menu modification ✅
* other menu modification ❌
* admin collection access ❌

### Admin

* authorized operations ✅

### Anonymous

```text
sensitive data → ❌
sensitive writes → ❌
```

---

# PHASE 21 — PENETRATION / ATTACK TESTING

Controlled testing.

We'll simulate:

```text
Modified client
Fake role
Fake shopId
Fake order total
Fake order status
Repeated OTP
Repeated order
Unauthorized Firestore access
Unauthorized Storage access
Invalid file upload
Invalid quantities
Invalid IDs
Concurrent requests
```

Goal:

```text
ATTACK
  ↓
SERVER/RULE
  ↓
BLOCK
  ↓
LOG if important
```

---

# PHASE 22 — RELEASE SECURITY

Before Play Store:

### Android

* Production keystore
* Debug signing removed
* Release configuration
* Obfuscation where appropriate
* Debug logs removed/restricted
* App Check production configuration
* Firebase production rules deployed

### Current blocker

Audit ke according:

```kotlin
release {
    signingConfig = signingConfigs.getByName("debug")
}
```

❌

Production release se pehle fix compulsory.

---

# PHASE 23 — OLD ANDROID COMPATIBILITY

Audit ne ye bhi identify kiya:

```text
arm64-v8a only
```

Therefore older 32-bit devices install nahi kar paayenge.

Ye **security issue nahi**, compatibility decision hai.

Hum separately decide karenge:

```text
arm64 only
```

ya

```text
arm64 + armeabi-v7a
```

---

# PHASE 24 — SECURITY INCIDENT RECOVERY

Agar kabhi compromise ho:

```text
Detect
  ↓
Identify
  ↓
Contain
  ↓
Revoke access
  ↓
Disable compromised credentials
  ↓
Restore/repair data
  ↓
Audit
  ↓
Patch
  ↓
Resume service
```

Admin ke paas emergency controls hone chahiye.

---

# 🧱 FINAL YummBU SECURITY STACK

Ultimately:

```text
                    ┌───────────────────┐
                    │     YummBU        │
                    └─────────┬─────────┘
                              │
                     WhatsApp Verification
                              │
                              ▼
                    Firebase Authentication
                              │
                         Firebase UID
                              │
                  ┌───────────┴───────────┐
                  │                       │
             Authentication         Authorization
                  │                       │
                  │                Custom Claims /
                  │                Server checks
                  │                       │
                  └───────────┬───────────┘
                              │
                         Firebase App Check
                              │
                              ▼
                     Cloud Functions /
                      Secure Backend
                              │
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
          Firestore        Storage            FCM
              │               │                │
              ▼               ▼                ▼
       Security Rules   Storage Rules    Token Security
              │
              ▼
       Server-side Validation
              │
      ┌───────┼────────┐
      ▼       ▼        ▼
   Orders   Pricing   Roles
      │
      ▼
 Abuse / Rate Limiting
      │
      ▼
 Logging & Monitoring
      │
      ▼
 Incident Recovery
```

## 🎯 Aur implementation order bhi ab lock kar sakte hain

Tumhare pehle wale plan ko refine karke:

### **PHASE 1 — Identity Foundation**

**1.1 → 1.5**

1. Authentication architecture
2. WhatsApp OTP
3. Firebase Auth identity
4. User creation/session
5. Role foundation

### **PHASE 2 — Authorization & Firebase Security**

**2.1 → 2.8**

1. Custom Claims / role authorization
2. Firestore rules
3. Order authorization
4. Order state machine
5. Storage rules
6. Device-token security
7. App Check
8. Security-rule emulator testing

### **PHASE 3 — Abuse + Backend Hardening**

1. Server-side order creation
2. Server-side price calculation
3. OTP rate limiting
4. Order spam protection
5. Global OTP circuit breaker
6. Cloud Function hardening
7. Scheduled order expiry
8. Logging/monitoring

### **PHASE 4 — Attack Testing**

```text
IDOR
Role spoofing
Price tampering
Status tampering
OTP flooding
Order flooding
Storage abuse
Firestore abuse
Session abuse
```

### **PHASE 5 — Production Gate**

```text
Secrets
Rules
App Check
Release signing
Logs
Error messages
Firebase production config
Pen-test
Regression tests
Final build
```

---

### One thing I would **not** do

Claude's audit mein kuch recommendations ko hum automatically "must implement" nahi maanenge.

For example:

* hardware MFA ❌
* unnecessary encryption layers ❌
* overly complicated session system ❌
* excessive logging ❌
* huge infrastructure like Redis if Firebase-native controls are sufficient ❌

**YummBU university-scale app hai**, isliye goal hoga:

> **Maximum practical security + minimum unnecessary complexity + controlled Firebase cost + no compromise on user experience.**

Aur existing **UI/UX frozen** rahega. Security implementation UI ko redesign nahi karegi.

**Ye structure ab hamara Security Master Plan maan sakte hain.** Iske baad implementation ko isi sequence mein one-by-one karna safest rahega.
