# 00 — Project Overview

## 1. App Identity & Name
- **App Name:** **BU Gate2Eat**
- **Tagline:** Everything around Bennett. One app. One tap.
- **Package Name / Application ID:** `com.bugate2eat.app` / `bugate2eat_app`

## 2. Business Goal & Problem Statement
Bennett University students (~6,000–7,000 students) order food daily from local vendors located right outside Bennett Gate No. 2 (Rajat Shop, Nayan Shop, etc.).
Previously, ordering involved manual phone calls or unformatted WhatsApp chats, causing long waiting times, misplaced orders, and payment disputes.

## 3. Product Solution & Zero-Friction Vision
**BU Gate2Eat** provides a streamlined, zero-login mobile application for Bennett University students:
1. **Zero Login Friction**: Student enters Name, 10-digit Phone, and Age once on first launch (stored locally in `SharedPreferences`).
2. **Shop & Menu Browsing**: Student browses verified Gate 2 shops (Rajat Shop & Nayan Shop) with real-time menu items, prices, veg/non-veg tags, and search/filtering.
3. **Cart & WhatsApp Order Generation**: Student adds items to cart and taps **Place Order via WhatsApp**. The app constructs a structured text message and deep-links directly into the vendor's WhatsApp chat (`+91 8295643910` or `+91 8875344034`).
4. **Pickup at Gate 2**: Vendor receives structured order on WhatsApp, prepares food, and student collects & pays at Bennett Gate No. 2.

## 4. Target Audience
- **Primary Users:** Bennett University Students (Hostellers & Day Scholars).
- **Secondary Users:** Local food vendors near Bennett Gate 2 (Rajat Shop, Nayan Shop).

## 5. Business Model & Scope
- **Current Scope (MVP):** 100% Free for students and vendors. No payment gateway integration required.
- **Vendor Workflow Impact:** **0% Workflow Change**. Vendors do not need to install an app, create accounts, or manage online dashboards. Orders arrive on their personal WhatsApp number.
