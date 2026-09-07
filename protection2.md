😂 Got it. For this conversation, I’ll act as Claude — specifically as the senior security architect you asked for.

I have the complete YummBU context.

One important limitation: I don’t have access to your actual YummBU codebase in this chat, only the architecture/context you provided. So I can give you the architecture-level security audit now, but I cannot honestly claim I inspected your actual Flutter files, Firestore rules, Storage rules, or backend.

🔐 YummBU Security Assessment — Claude Review

Executive verdict

Your security roadmap is directionally good, but I would change the order significantly.

The biggest mistake would be treating:

Role system → routes → Firestore → order security

as four mostly independent features.

They are actually one security system:

Authentication → Identity → Authorization → Data authorization → Server-side business logic

And the most important principle for YummBU is:

Assume the Flutter client is completely hostile.

A user can modify the APK/web client, inspect requests, replay requests, alter local storage, change IDs, alter prices, and bypass every UI check.

Your own threat model already correctly recognizes this.

1. 🔴 CRITICAL risks

These are the things I would consider non-negotiable before public launch.

1. Client-controlled roles

If the current system determines:

phone number → "admin"

or:

localStorage → role = admin

that is a critical vulnerability.

An attacker must never be able to promote themselves by changing client-side data.

Your temporary phone-number role detection should therefore be treated strictly as development code. Your own architecture already identifies this as temporary/insecure.

Correct model:

Authenticated identity
        ↓
Server-controlled authorization
        ↓
Role
        ↓
Permissions

Not:

Flutter
 ↓
"I am admin"

2. Firestore rules are the real security boundary

If your Firestore rules are permissive, almost everything else becomes irrelevant.

An attacker doesn't need your Flutter UI.

They can potentially construct their own client and communicate directly with Firebase.

Therefore:

Flutter UI
     ↓
Client validation
     ↓
Firestore Rules
     ↓
Server-side validation where necessary

The Rules/backend, not the Flutter UI, must enforce authorization.

3. Customer-created order data cannot be trusted

This is probably your most important business-logic vulnerability.

Suppose Flutter sends:

{
  "shopId": "shop123",
  "items": [
    {
      "itemId": "burger",
      "price": 10,
      "quantity": 1
    }
  ],
  "total": 10
}

The attacker can simply change it to:

{
  "price": 1,
  "total": 1
}

or:

{
  "shopId": "competitorShop"
}

or:

{
  "quantity": 999999
}

Therefore price and total must never be treated as authoritative merely because the Flutter client calculated them.

Your threat model explicitly calls this out.

For serious order integrity, the server should validate/reconstruct critical values from trusted menu data.

4. Order status manipulation

This must not be:

client says:
status = delivered

The system must verify:

current = accepted
actor = authorized shopkeeper
shopkeeper belongs to order.shopId
requested = delivered

Then allow the transition.

Conceptually:

placed
 ├── accepted → delivered
 ├── rejected
 └── cancelled

Everything else is rejected.

Your defined lifecycle is correct.

5. Shopkeeper → shop authorization

This is another critical authorization boundary.

Don't merely check:

role == shopkeeper

You need:

role == shopkeeper
AND
shopkeeper is assigned to this shop

Otherwise:

Shopkeeper A
     ↓
changes shopId
     ↓
Shop B data

becomes possible.

The authorization relationship should be server-controlled.

2. 🔴 OTP architecture deserves special attention

Your concern about WhatsApp OTP cost attacks is completely legitimate.

An attacker doesn't necessarily need to hack an account.

They can simply abuse your OTP endpoint:

BOT
 ↓
request OTP
 ↓
request OTP
 ↓
request OTP
 ↓
...
💰💰💰

Your planned controls are good, but the Flutter client cannot enforce them.

For example:

if (secondsRemaining > 0) return;

is useful UX, but provides almost zero security against a custom client.

The actual rate limits need to be enforced server-side.

I would use multiple layers:

Request OTP
    ↓
App Check / bot signal
    ↓
IP/network rate limit
    ↓
phone-number rate limit
    ↓
device/session signal where appropriate
    ↓
global provider protection
    ↓
send OTP

And separately:

OTP verification
    ↓
expiration
    ↓
attempt limit
    ↓
temporary lockout

Don't rely on a single limit.

3. 🟠 Your roadmap order should change

Your current roadmap puts authentication quite late.

I would not build the final authorization architecture around a fake identity and then replace the identity later.

Instead, build the system around an abstraction such as:

CurrentIdentity
      ↓
Authorization
      ↓
Permissions

During development:

DevelopmentIdentityProvider

At launch:

WhatsAppOtpIdentityProvider

The authorization layer should not care how the user authenticated.

That gives you:

Development authentication
          ↓
       identity
          ↓
     authorization
          ↓
      Firestore

and later:

WhatsApp OTP
          ↓
       identity
          ↓
     authorization
          ↓
      Firestore

This matches your requirement that the temporary identity should eventually be replaceable without rewriting the authorization architecture.

4. 🟠 Recommended architecture

For YummBU, I'd aim for:

                 ┌─────────────────┐
                 │     Flutter     │
                 │     Client      │
                 └────────┬────────┘
                          │
                  NEVER TRUST THIS
                          │
             ┌────────────▼────────────┐
             │ Firebase Authentication │
             └────────────┬────────────┘
                          │
                    authenticated
                       identity
                          │
             ┌────────────▼────────────┐
             │ Authorization / Claims  │
             │                         │
             │ customer                │
             │ shopkeeper + shop IDs   │
             │ admin                   │
             └────────────┬────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
      ┌───────▼────────┐     ┌────────▼────────┐
      │ Firestore Rules│     │ Server Functions│
      │                │     │ / Backend       │
      └────────────────┘     └─────────────────┘

The exact split between Firestore Rules and backend functions depends on your actual schema and operations.

5. What should be client-side vs server-side?

Client-side

Good for:

UI validation

quantity limits for UX

empty-cart checks

displaying errors

navigation

preventing accidental double taps

optimistic UI

But none of these should be your security boundary.

Firestore Rules

Good for:

who can read a document

who can write it

ownership

shopkeeper/shop relationship

immutable fields

role authorization

preventing unauthorized status changes

Server-side

Use for operations where the client should not be authoritative, especially:

sensitive role assignment

admin operations

OTP generation/verification integration

provider secrets

trusted price calculation

complicated order validation

security-sensitive state transitions

privileged administrative operations

6. 🟠 Firebase App Check

App Check is valuable, but don't misunderstand it.

It helps answer:

"Is this request probably coming from my legitimate app?"

It does not answer:

"Is this user authorized to modify this order?"

Therefore:

App Check
     +
Authentication
     +
Firestore Rules
     +
Server validation

is much stronger than App Check alone.

I would introduce it during hardening/testing and gradually move toward enforcement rather than turning it on blindly and discovering legitimate clients are broken.

Your prompt is correct to specifically ask how it behaves across Flutter Web and Android.

7. 🟠 Admin security

Admin is fundamentally different from customer security.

I would recommend:

Normal user
   ↓
authentication
   ↓
normal authorization

but:

Admin
   ↓
authentication
   ↓
admin authorization
   ↓
additional protection
   ↓
sensitive operation
   ↓
audit log

For particularly dangerous actions:

deleting shops

changing admin access

assigning shopkeepers

modifying security configuration

consider requiring an additional verification step.

Also maintain an audit trail:

WHO
WHAT
WHEN
TARGET
RESULT

Example:

admin123
changed shopkeeper assignment
shop_42
2026-08-28 12:42
success

8. 🟡 Don't overbuild the 4-device system yet

Your proposed:

maximum 4 devices → fifth device removes oldest

is technically possible.

But for YummBU's current scale, I would classify it Medium/Low priority unless there is a specific operational reason.

First solve:

authentication
authorization
session revocation
role changes
compromised account handling

Then add sophisticated device management if the real-world need appears.

Don't spend weeks building a perfect device-session system while a Firestore rule can still be bypassed.

9. 🟠 Storage security

Your image system needs two levels:

Authorization

/customer
    READ public
    WRITE NO

/shopkeeper/shop123
    WRITE only if assigned to shop123

/admin
    authorized

File restrictions

Enforce things such as:

content type

reasonable file size

correct path

authorized uploader

controlled deletion

Also think about orphaned images when menu/shop records are deleted.

10. 🟡 Spam protection

Don't treat spam as only an OTP problem.

You have several attack surfaces:

OTP
 ↓
Accounts
 ↓
Orders
 ↓
Firestore
 ↓
Storage
 ↓
Backend

For example, someone could create legitimate accounts and then spam:

100 fake orders

against one shop.

So I'd eventually implement:

per-user order rate limits

duplicate-order detection

reasonable quantity limits

cooldowns

suspicious activity detection

server-side idempotency for order creation where appropriate

But avoid aggressive limits that punish genuine students.

11. 🟡 Logging

You correctly don't want to log everything.

I'd divide logs into:

Security-critical

Always worth recording:

admin authorization changes

shopkeeper assignment changes

critical admin actions

repeated authentication failures

abnormal OTP activity

suspicious authorization failures

important backend failures

Normal application events

Don't necessarily persist everything forever.

You don't need:

user opened menu
user scrolled
user clicked burger

as permanent audit records.

12. 🔥 The biggest change I'd make to your roadmap

Your current:

PHASE 1
Role
Routes
Firestore
Orders
Storage

PHASE 2
Spam
Cleanup
Audit

PHASE 3
OTP
Backend
Sessions
Logging
Admin protection

I'd change it to:

PHASE 0 — Security architecture

Define trust boundaries

Define roles/permissions

Define identity abstraction

Define authoritative vs client data

Define order state machine

Define sensitive operations

↓

PHASE 1 — Identity + Authorization Foundation

Authentication interface

Development identity

Role model

Shopkeeper → shop assignment

Authorization helpers

Remove client-controlled role assumptions

↓

PHASE 2 — Firebase Security

Firestore Rules

Storage Rules

Ownership checks

Field-level protection

Role protection

Shop isolation

↓

PHASE 3 — Order Integrity

Server-authoritative validation

Price validation

Quantity validation

Item availability

Shop validation

State-machine enforcement

Duplicate-order protection

↓

PHASE 4 — Production Authentication

WhatsApp OTP

OTP backend

OTP expiration

attempt limits

rate limits

provider-secret protection

account creation protection

↓

PHASE 5 — Abuse Protection

OTP abuse

order spam

API abuse

App Check

suspicious activity

cost protection

↓

PHASE 6 — Admin + Sessions

stronger admin protection

MFA/additional verification where appropriate

session revocation

role-change invalidation

account recovery

audit logs

↓

PHASE 7 — Production Hardening

secrets

dependency audit

debug cleanup

environment separation

backups

monitoring

incident response

↓

PHASE 8 — Attack Testing

Then actively test:

Customer → Customer data
Customer → Shopkeeper data
Customer → Admin
Shopkeeper A → Shop B
Shopkeeper → Admin
Modified price
Modified total
Modified shopId
Modified orderId
Modified status
Fake menu item
Unavailable item
Duplicate order
OTP spam
OTP guessing
Storage abuse
Firestore direct access
Replay attacks

Then launch.

Final verdict

Your current security thinking is actually strong for an early-stage project. The threat model is much better than a generic "add Firebase Rules" approach.

The biggest things I would change are:

AreaVerdict



Threat model

🟢 Very good

Customer/shop/admin separation

🟢 Correct

"Never trust Flutter" principle

🟢 Essential

Firestore security

🔴 Critical

Order integrity

🔴 Critical

Client-side role detection

🔴 Remove before production

WhatsApp OTP

🔴 Needs server-side architecture

OTP cost protection

🔴 Critical before launch

App Check

🟢 Useful, but not authorization

Admin protection

🔴 High priority

Logging

🟢 Necessary, but keep selective

4-device management

🟡 Probably premature

Backup/recovery

🟠 Missing from early phases

Dependency/release security

🟠 Should be before launch

Current phase ordering

🟠 Needs restructuring

And one particularly important point:

Do not start implementing individual security features until the authorization model is designed as a whole. Otherwise you risk creating five individually "secure" features that don't compose into a secure system.

Your ultimate security goal is exactly the right one:

A compromised customer should remain a customer.
A compromised shopkeeper should remain confined to their shop.
A compromised account should not compromise the platform.
And an admin compromise should have additional defenses and recovery mechanisms.

If you give me the actual YummBU codebase, I can do the next level: a file-by-file security audit and identify the concrete vulnerabilities rather than only reviewing the architecture.