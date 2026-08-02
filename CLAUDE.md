# BU Gate2Eat v1

## Project Overview
A Flutter mobile app for local food shops and students near Bennett University (Gate No. 2), Greater Noida. The app simplifies WhatsApp ordering for campus food spots.

## Tech Stack
- **Framework**: Flutter (Dart)
- **State Management**: Provider / Riverpod (prefer Riverpod for new features)
- **Backend**: Firebase (Firestore, Auth, Storage, Cloud Functions)
- **Architecture**: Feature-first folder structure with clean architecture layers
- **Minimum SDK**: Flutter 3.x, Dart 3.x

## Project Structure
```
lib/
├── core/              # Shared utilities, constants, theme, routing
│   ├── constants/     # App-wide constants, API keys, colors
│   ├── theme/         # App theme data, text styles, color scheme
│   ├── utils/         # Helper functions, extensions, formatters
│   └── widgets/       # Shared/reusable widgets
├── features/          # Feature modules (each self-contained)
│   ├── auth/          # Authentication (login, signup, profile)
│   ├── home/          # Home screen, feed
│   ├── explore/       # Discover businesses, places, events
│   ├── business/      # Business listings, details, reviews
│   └── settings/      # App settings, preferences
├── models/            # Data models / entities
├── services/          # API services, repositories
└── main.dart          # App entry point
```

## Coding Standards
- Use `const` constructors wherever possible
- Prefer named parameters for widgets
- All widgets should be extracted into separate files when they exceed 80 lines
- Use `part` / `part of` sparingly — prefer imports
- Follow effective Dart style guide: https://dart.dev/effective-dart
- Write doc comments for all public APIs
- Use meaningful variable and function names (no abbreviations)

## Naming Conventions
- Files: `snake_case.dart`
- Classes: `PascalCase`
- Variables/functions: `camelCase`
- Constants: `camelCase` (not SCREAMING_CASE per Dart convention)
- Private members: `_prefixed`

## Git Workflow
- Commit messages: `type(scope): description` (e.g., `feat(auth): add Google sign-in`)
- Types: feat, fix, refactor, style, docs, test, chore
- Branch naming: `feature/short-description`, `fix/issue-description`

## Testing
- Unit tests in `test/` mirroring `lib/` structure
- Widget tests for all screens
- Run tests: `flutter test`
- Run with coverage: `flutter test --coverage`

## Build & Run
- Dev: `flutter run`
- Build APK: `flutter build apk --release`
- Build iOS: `flutter build ios --release`
- Analyze: `flutter analyze`
- Format: `dart format .`
