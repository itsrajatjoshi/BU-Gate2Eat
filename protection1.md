Got it. For this conversation, I’ll act as Claude — specifically as the Senior Application Security Architect / Firebase Security Expert you asked for.

One important distinction: I have YummBU’s architecture/context, but I do not have the actual Flutter codebase, Firestore rules, Storage rules, or backend source here. So I will not pretend I inspected code I haven't seen. The assessment below is therefore an architecture/threat-model review, not a code audit. Your supplied YummBU specification explicitly requires the client to be treated as untrusted and identifies Firebase, roles, orders, OTP, storage and business abuse as security boundaries.

🔐 YummBU Security Assessment

Executive verdict

Your roadmap is directionally correct, but the implementation order needs to change.

The biggest architectural mistake would be treating:

Flutter UI → Firebase → security

as if the Flutter application were trustworthy.

It isn't.

An attacker can create their own client, modify requests, manipulate local state, replay requests, and communicate directly with Firebase/backend services. Your own threat model correctly recognizes this.

The security architecture should instead look approximately like:

                 ┌─────────────────────┐
                 │   Untrusted Client  │
                 │      Flutter        │
                 └──────────┬──────────┘
                            │
                     Authenticated
                       request
                            │
                ┌───────────▼───────────┐
                │   Abuse Protection     │
                │ App Check / limits     │
                └───────────┬───────────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
       ┌──────▼──────┐             ┌──────▼──────┐
       │  Firestore  │             │   Backend   │
       │ Security    │             │ / Functions │
       │   Rules     │             │             │
       └──────┬──────┘             └──────┬──────┘
              │                           │
              └─────────────┬─────────────┘
                            │
                    Trusted operations
                            │
                  ┌─────────▼─────────┐
                  │   Firebase data   │
                  │ / external APIs   │
                  └───────────────────┘

1. Risk classification

🔴 CRITICAL

These can potentially compromise the entire platform:

Client-controlled role/authorization

Admin authorization stored only in client/local storage

Open Firestore rules

Shopkeeper authorization based only on shopId supplied by client

Customer-controlled order price/total being trusted

Client-controlled order status

Secrets/API credentials inside Flutter

WhatsApp OTP endpoint without strong server-side rate limiting

Backend privilege escalation

Production Firebase project accidentally using development rules

🟠 HIGH

Cross-user order access

Cross-shop shopkeeper access

Unauthorized Storage upload/delete

OTP enumeration/guessing

Order spam

Duplicate order creation

Replay attacks

Missing session revocation

Weak admin protection

Excessive Firebase/API abuse

Missing audit trail for privileged operations

No recovery strategy

🟡 MEDIUM

Excessive information in errors

Weak device/session management

Excessive logging

Dependency vulnerabilities

Debug configuration leaking into release

Unlimited image uploads

Missing cleanup of abandoned Storage objects

Missing monitoring/alerting

🟢 LOW

Code obfuscation

Advanced device fingerprinting

Sophisticated behavioral analytics

Extremely granular security telemetry

Four-device enforcement for shopkeepers

Some of these are useful later but not launch blockers.

2. Your biggest vulnerability: authorization

This is the area I would prioritize above almost everything else.

You have:

Customer
Shopkeeper
Admin

But the important question isn't:

"What role does the Flutter app think I have?"

It is:

"What role does the trusted backend/Firebase authorization layer know I have?"

For example, this is NOT security:

if (userRole == "admin") {
   showAdminPanel();
}

And neither is:

SharedPreferences:
role = "admin";

An attacker controls the client.

They could theoretically modify:

customer → admin
shopId A → shopId B
orderId 123 → orderId 456
price ₹100 → ₹1
status placed → delivered

Therefore:

Client-side checks = UX

Server/Firebase authorization = security

Your specification already identifies this exact trust boundary.

3. Recommended role architecture

I would separate identity, role, and shop assignment.

Conceptually:

Firebase Auth UID
        │
        ▼
     Identity
        │
        ├── role = customer
        │
        ├── role = shopkeeper
        │          │
        │          └── assignedShopIds
        │
        └── role = admin

But don't allow the client to write its own role.

For example:

users/{uid}

could contain profile information, while authorization-sensitive information is controlled through trusted mechanisms.

For Firebase, custom claims are particularly useful for coarse-grained roles, while shop-specific authorization can be enforced through trusted data/rules.

The exact implementation depends on your final authentication architecture.

4. Customer authorization

A customer should effectively have:

READ:
public shops
public menus
own profile
own orders

CREATE:
valid order

UPDATE:
only explicitly permitted fields/actions

DELETE:
only permitted resources/actions

They should not be able to directly modify:

order.customerId
order.shopId
order.price
order.total
order.status
order.createdAt

simply because those fields appear in a Firestore document.

5. Shopkeeper authorization

This is one of the most important YummBU-specific risks.

Suppose Shopkeeper A sends:

shopId = SHOP_B

to your application.

Your backend/rules must NOT say:

"Okay, user provided SHOP_B, therefore let them access SHOP_B."

Instead:

authenticated UID
       ↓
trusted shopkeeper assignment
       ↓
SHOP_A

Then:

requested shop = SHOP_B

SHOP_B != assigned shop

→ DENY

This protects against:

IDOR

horizontal privilege escalation

cross-shop order access

cross-shop menu modification

cross-shop image deletion

Your requirement that Shopkeeper A must never access Shopkeeper B's data is therefore a server-side authorization requirement, not merely a UI requirement.

6. Order security is more complicated than it looks

Your current order lifecycle is:

PLACED
   ↓
ACCEPTED
   ↓
DELIVERED

with:

PLACED → REJECTED
PLACED → CANCELLED

That's good.

But don't implement this as:

update({
  "status": newStatus
});

with the client deciding newStatus.

Because an attacker could theoretically send:

status = delivered

directly.

Instead, authorization should enforce the state machine.

Conceptually:

PLACED
 ├── ACCEPTED
 ├── REJECTED
 └── CANCELLED

ACCEPTED
 └── DELIVERED

REJECTED
 └── terminal

CANCELLED
 └── terminal

DELIVERED
 └── terminal

And:

DELIVERED → ACCEPTED

must fail regardless of what the Flutter application says.

7. The price problem

This is CRITICAL if you eventually add payment.

Never treat:

clientPrice
clientTotal

as authoritative.

Suppose the menu says:

Burger = ₹120

The attacker submits:

Burger = ₹1

If your backend simply stores:

price: 1

you have an integrity vulnerability.

The safer architecture is:

Client
  ↓
itemId + quantity
  ↓
trusted backend
  ↓
fetch current menu data
  ↓
verify availability
  ↓
verify shop
  ↓
calculate price
  ↓
calculate total
  ↓
create order

The client can calculate totals for display, but the trusted system should determine authoritative values.

This becomes even more important when you introduce payments.

8. Order duplication / replay

Your roadmap currently puts spam protection relatively late.

I would move basic order-abuse protection earlier.

Imagine:

POST /createOrder
POST /createOrder
POST /createOrder
POST /createOrder
...

within milliseconds.

You need protection against:

double taps

retries

network retries

malicious automation

replayed requests

Use an idempotency mechanism / client-generated request ID where appropriate.

Conceptually:

requestId = ABC123

first request:
ABC123 → create order

second request:
ABC123 → already processed

→ don't create another order

This is much better than relying only on:

_isLoading = true;

because _isLoading exists on the client and therefore isn't a security boundary.

9. WhatsApp OTP architecture

This is another major area.

Do not build:

Flutter
   ↓
WhatsApp API directly

if that requires embedding a secret API key in Flutter.

That would effectively mean:

Flutter APK
   ↓
attacker extracts credentials
   ↓
attacker uses your WhatsApp provider
   ↓
your bill

Instead:

Flutter
   ↓
Your authentication backend
   ↓
Rate limits / abuse checks
   ↓
WhatsApp provider

The provider secret stays server-side.

10. OTP abuse protection

Your concern here is absolutely legitimate.

An attacker doesn't need to hack an account.

They can simply attack your wallet.

For example:

100 requests
×
₹X OTP cost
=
unexpected bill

You need multiple independent controls.

Per phone number

Example conceptual policy:

minimum resend interval
daily/hourly request limit
maximum verification attempts
OTP expiration

Per IP/network

Useful against simple automation.

But do not rely exclusively on IP, because university networks can put many legitimate students behind the same public IP.

Per device/session

Can add another signal, but don't treat device identifiers as cryptographically trustworthy.

Global emergency protection

This is important.

You should have a mechanism that can effectively say:

OTP traffic abnormal
        ↓
temporarily disable / restrict OTP issuance

rather than allowing an attacker to continuously generate costs.

Monitoring

You should know if:

OTP requests suddenly increase 20×

before you discover it through a bill.

11. OTP guessing

Never accept unlimited attempts.

Conceptually:

OTP generated
   ↓
expires after short period
   ↓
limited verification attempts
   ↓
too many failures
   ↓
temporary lock/rate limit

And importantly:

Don't reveal whether a phone number is registered if that information isn't necessary.

Otherwise attackers may enumerate users.

12. Firebase App Check

App Check is useful.

But there is a critical misconception to avoid:

App Check is not authentication and is not authorization.

It can help distinguish requests coming from legitimate instances of your application from arbitrary clients, depending on platform/configuration.

But an attacker who legitimately possesses an authenticated account is still an authenticated attacker.

Therefore:

App Check
+
Authentication
+
Firestore Rules
+
Backend authorization
+
Rate limiting

not:

App Check = security

I'd introduce it during hardening and test it thoroughly before enforcement.

13. Firestore Rules

This is one of your launch blockers.

You want rules that implement deny-by-default thinking.

Not:

allow read, write: if true;

And not:

allow write: if request.auth != null;

because that only proves:

"This person is logged in."

It doesn't prove:

"This person is allowed to modify THIS document."

You need authorization based on things like:

request.auth.uid
role
shop assignment
resource.data
request.resource.data
allowed fields
current status
requested status

The exact rules must be derived from your actual schema.

14. Storage security

Your Storage model should mirror your authorization model.

For example conceptually:

shops/{shopId}/...

Then:

customer:
    read public images

shopkeeper:
    write only assigned shop

admin:
    authorized management

Also enforce:

content type

maximum file size

upload path restrictions

delete permissions

overwrite permissions

Don't assume that because the UI only displays an "Upload Image" button to shopkeepers, customers can't upload.

They can potentially bypass the UI entirely.

15. Admin security

I consider admin account compromise one of your highest-impact scenarios.

You should have:

Strong authentication

WhatsApp OTP alone may not be sufficient as the only protection for extremely sensitive administrative operations.

At minimum, consider stronger authentication for admin.

Potentially:

normal login
      ↓
additional admin verification
      ↓
admin session

and/or MFA depending on your final authentication infrastructure.

Audit logs

For example:

ADMIN
DELETE_SHOP
shopId=XYZ
timestamp=...

Session revocation

If admin credentials/session are compromised:

revoke
↓
force reauthentication

Sensitive action protection

Particularly for:

deleting shops

assigning shopkeepers

changing roles

deleting critical data

changing security settings

16. Development shortcuts

This is something I would aggressively search for in the actual codebase.

Especially:

if phone == "..."
    role = admin

or:

SharedPreferences:
isAdmin = true

or:

if (kDebugMode)
   bypassAuth()

or seeded credentials.

Development shortcuts are dangerous because developers often forget them.

I would specifically search the repository for:

admin
role
isAdmin
shopkeeper
phone
uid
debug
bypass
test
seed
mock
password
token
secret
apiKey

and inspect every security-sensitive result.

17. Secrets

Safe-ish to expose in a Firebase client

Some Firebase configuration values are designed to exist in the client.

But that does not mean every credential associated with Firebase is safe to expose.

Never put sensitive credentials such as:

service account private keys
WhatsApp provider secrets
backend signing secrets
payment secret keys
database administrative credentials

inside Flutter.

Also don't commit them to GitHub.

And don't assume:

.gitignore

undoes a secret that has already been committed to Git history.

18. Error handling

Don't expose:

Firebase path:
shops/abc/orders/xyz

Exception:
permission-denied
stack trace...

to normal users.

Instead:

Something went wrong.
Please try again.

while developers receive useful diagnostic information through controlled logging.

19. Logging

Don't log everything.

That increases:

cost

noise

privacy risk

I'd prioritize security-sensitive events:

admin role changes
shopkeeper assignment changes
critical shop modifications
order-state anomalies
repeated authentication failures
OTP abuse
authorization failures
backend errors

You should also avoid putting OTPs, authentication secrets, or unnecessary personal information into logs.

20. Backup and recovery

This is missing from many student projects.

Security isn't:

Prevent attack

It's:

Prevent
+
Detect
+
Contain
+
Recover

For YummBU, you should have a plan for:

Firestore accidental deletion
        ↓
restore/recovery

and:

compromised admin
        ↓
revoke access
        ↓
rotate credentials
        ↓
inspect audit events
        ↓
restore damaged data if necessary

21. Your roadmap — corrected

I would change your roadmap to this:

🔴 PHASE 0 — SECURITY FOUNDATION

Before implementing fancy security features:

0.1 Threat model

0.2 Define trust boundaries

0.3 Define roles

0.4 Define authorization matrix

0.5 Define sensitive fields

0.6 Define order state machine

0.7 Identify all privileged operations

This gives you the security specification.

🔴 PHASE 1 — AUTHORIZATION FOUNDATION

1.1 Real authenticated identity abstraction

Even if temporary authentication is still being used, structure the application around an identity abstraction that can later map to Firebase Auth.

1.2 Role authorization

Customer / Shopkeeper / Admin.

1.3 Shopkeeper → shop authorization

This is critical.

1.4 Firestore Rules

Lock the database down.

1.5 Storage Rules

Lock images down.

1.6 Route guards

Useful, but last in this phase conceptually because they're UX protection, not the actual security boundary.

🔴 PHASE 2 — ORDER INTEGRITY

2.1 Order ownership

2.2 Shop ownership

2.3 Allowed state transitions

2.4 Protected fields

2.5 Price validation

2.6 Quantity validation

2.7 Availability validation

2.8 Duplicate/replay protection

2.9 Server-side order creation where necessary

This is extremely important.

🟠 PHASE 3 — ABUSE PROTECTION

3.1 Order rate limiting

3.2 Duplicate request protection

3.3 Storage upload limits

3.4 Backend/API rate limiting

3.5 App Check

3.6 Suspicious activity detection

🟠 PHASE 4 — PRODUCTION SECURITY

4.1 Remove development shortcuts

4.2 Secret management

4.3 Production Firebase rules

4.4 Environment separation

4.5 Debug configuration removal

4.6 Dependency audit

4.7 Safe error handling

4.8 Logging

4.9 Audit trail

🔴 PHASE 5 — FINAL AUTHENTICATION

Now implement your WhatsApp authentication architecture.

Phone
 ↓
OTP request
 ↓
backend
 ↓
rate limits
 ↓
WhatsApp provider
 ↓
OTP verification
 ↓
authenticated identity
 ↓
authorization

Include:

5.1 OTP generation

5.2 OTP expiration

5.3 Attempt limits

5.4 Resend cooldown

5.5 Phone limits

5.6 Abuse protection

5.7 Global cost protection

5.8 Secure role assignment

5.9 Session management

5.10 Revocation

🔴 PHASE 6 — ADMIN HARDENING

6.1 Stronger admin authentication

6.2 MFA / additional verification where appropriate

6.3 Admin audit logs

6.4 Sensitive-action protection

6.5 Session revocation

6.6 Admin incident-response procedure

🔴 PHASE 7 — PRE-LAUNCH ATTACK TEST

This should happen before public launch, not merely as a generic "audit."

Test each trust boundary.

For example:

Customer → Customer

Can A read B's order?
Can A modify B's order?

Customer → Shopkeeper

Can customer modify menu?
Can customer upload shop image?

Customer → Admin

Can customer become admin?

Shopkeeper A → Shopkeeper B

Can A read B's orders?
Can A modify B's menu?
Can A delete B's images?

Client → Database

Can custom client bypass Flutter?

Order

Can price be manipulated?
Can total be manipulated?
Can status be manipulated?
Can shopId be manipulated?
Can orders be duplicated?

Authentication

Can OTP be spammed?
Can OTP be guessed?
Can sessions be reused?
Can revoked users continue accessing data?

22. What I would remove/change from your original roadmap

❌ Don't make route security a major security phase

Keep it, but understand:

route guard ≠ authorization

It's mostly client-side UX protection.

❌ Don't postpone all abuse protection until late

Basic order abuse/idempotency should exist when the order system becomes real.

❌ Don't wait until the final phase to think about backend architecture

Your future WhatsApp OTP architecture needs a trusted backend.

That architecture should be designed before you lock yourself into a Firebase-only client architecture.

❌ Don't assume Firebase App Check solves malicious clients

It doesn't.

❌ Four-device shopkeeper management is not a priority

Useful feature.

Not a launch-critical security control.

I'd put it much lower than:

authorization
Firestore Rules
order integrity
authentication
OTP protection
admin security
secrets
backup/recovery

23. What is missing from your original plan

The biggest missing pieces are:

🔴 Authorization matrix

Explicitly define:

ResourceCustomerShopkeeperAdmin







Public shops

Read

Read

Full

Own profile

Own

Own

Authorized

Own orders

Read/cancel allowed

—

Authorized

Shop orders

—

Assigned shop

Authorized

Menu

Read

Assigned shop

Full

Roles

❌

❌

Controlled

Shopkeeper assignment

❌

❌

Controlled

Security logs

❌

❌

Restricted

This matrix should become the basis of your actual rules.

🔴 Server-side business logic

Not every operation should be a direct Firestore write.

Particularly:

order creation
price calculation
privileged role changes
shopkeeper assignment
sensitive administrative actions
OTP operations

should be carefully evaluated for trusted backend enforcement.

🔴 Recovery

You need:

backup
restore
credential rotation
account revocation
incident response

🔴 Security testing

Not just:

"Does the UI work?"

But:

"What happens when I completely ignore the UI and attack the backend?"

24. Final architecture I'd aim for

For YummBU, I would target this:

                         YummBU
                            │
              ┌─────────────┴─────────────┐
              │                           │
          Flutter                      Admin UI
              │                           │
              └─────────────┬─────────────┘
                            │
                    Firebase Auth
                            │
                     authenticated UID
                            │
                  ┌─────────▼─────────┐
                  │ Authorization     │
                  │ role + ownership  │
                  └─────────┬─────────┘
                            │
                ┌───────────┴───────────┐
                │                       │
        Firestore Rules          Trusted Backend
                │                       │
                │                ┌──────┴──────┐
                │                │             │
                │             WhatsApp       Sensitive
                │               OTP          operations
                │
                ▼
             Firestore
                │
                ▼
             Storage

          + App Check
          + Rate limiting
          + Monitoring
          + Audit logs
          + Backup/recovery

🏁 Final verdict

Your original security thinking is actually quite good for a student project. The threat model isn't the problem.

The main thing I would change is the mindset:

Don't try to make Flutter secure. Make Flutter irrelevant to security decisions.

Flutter should tell the backend:

"I want to do X."

The trusted security layer decides:

"Are you actually allowed to do X?"

That single principle protects a huge portion of YummBU.

And your most important launch blockers are:

1. Authentication
2. Authorization
3. Firestore Rules
4. Storage Rules
5. Order integrity
6. Server-side validation
7. OTP abuse/cost protection
8. Admin protection
9. Secrets management
10. Backup + recovery
11. Security testing

Everything else is secondary.

I would not implement Phase 1.1 yet based only on this prompt. The next proper step is to inspect the actual YummBU codebase and produce a file-by-file security audit, because only then can we determine which of these risks actually exist versus which are merely architectural possibilities.