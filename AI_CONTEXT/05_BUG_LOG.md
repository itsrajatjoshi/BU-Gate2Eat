# 05 — Bug Log & Resolution History

| Date | Bug Description | Root Cause | Resolution / Fix Applied |
|---|---|---|---|
| **01-Aug-2026** | `ClassNotFoundException: Didn't find class com.bugate2eat.app.MainActivity` on app startup. | Package renaming left old Kotlin package path in `android/app/src/main/kotlin`. | Created [MainActivity.kt](file:///d:/app/BUGate2Eat%20App%20v1/android/app/src/main/kotlin/com/bugate2eat/app/MainActivity.kt) in package `com.bugate2eat.app`. |
| **01-Aug-2026** | Kotlin Gradle incremental build failed on Windows cross-drive compilation. | Gradle pub cache on `C:` drive and project on `D:` drive caused `IllegalArgumentException: different roots`. | Added `kotlin.incremental=false` to `android/gradle.properties`. |
| **01-Aug-2026** | Splash Screen stuck loading forever. | `main()` hung waiting for initial Firestore query before `runApp()`. | Made `SeedDataService` call non-blocking and added 1-second timeout to force-update check. |
| **01-Aug-2026** | WhatsApp URL Launcher failed on Android 11+. | Missing intent queries in AndroidManifest for `https` and `tel` schemes. | Added `<queries>` intent declarations for `https` and `tel` in `AndroidManifest.xml`. |
| **01-Aug-2026** | Firestore threw `PERMISSION_DENIED` on startup. | Firestore default security rules in Firebase Console were set to `allow read, write: if false;`. | Published rule `allow read, write: if true;` in Firebase Console. |
| **01-Aug-2026** | Installed APK on second phone showed "Something went wrong". | `AndroidManifest.xml` in `main` was missing `<uses-permission android:name="android.permission.INTERNET"/>`. | Added `INTERNET` and `ACCESS_NETWORK_STATE` permissions to `android/app/src/main/AndroidManifest.xml`. |
| **01-Aug-2026** | Manually edited prices in Firestore were overwritten on app launch. | `SeedDataService` ran `.set(..., SetOptions(merge: true))` unconditionally on every launch. | Added guard check `if (rajatDoc.exists && nayanDoc.exists) return;` so seeding skips when shops exist. |
