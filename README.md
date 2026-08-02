# 🍔 BU Gate2Eat

A mobile app connecting students and local food shops near **Bennett University** (Gate No. 2), Greater Noida.

## ✨ Features

- 🏪 **Discover Local Businesses** — Restaurants, cafes, shops, services near campus
- ⭐ **Reviews & Ratings** — Community-driven reviews
- 📍 **Map View** — Find places on an interactive map
- 🔔 **Deals & Events** — Stay updated on local offers and events
- 👤 **User Profiles** — Personalized experience

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x or later)
- [Dart SDK](https://dart.dev/get-dart) (3.x or later)
- Android Studio / VS Code with Flutter extension
- Firebase project configured

### Setup

```bash
# Clone the repository
git clone <repo-url>
cd near-bennett-app

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Environment Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add Android and iOS apps to your Firebase project
3. Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
4. Run `flutterfire configure` to generate `firebase_options.dart`

## 📁 Project Structure

```
lib/
├── core/          # Theme, constants, utilities, shared widgets
├── features/      # Feature modules (auth, home, explore, etc.)
├── models/        # Data models
├── services/      # API & Firebase services
└── main.dart      # Entry point
```

## 🧪 Testing

```bash
flutter test                    # Run all tests
flutter test --coverage         # With coverage report
```

## 📦 Building

```bash
flutter build apk --release    # Android APK
flutter build appbundle         # Android App Bundle
flutter build ios --release    # iOS (requires macOS)
```

## 🤝 Contributing

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Commit changes: `git commit -m "feat(scope): description"`
3. Push and open a Pull Request

## 📄 License

This project is private and proprietary.
