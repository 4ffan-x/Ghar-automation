# Progress

## Phase 0 — Environment and skeleton

- Flutter 3.50.0 (stable) and Dart 3.14.0 are installed. Android SDK 37, NDK `28.2.13676358`, toolchain, and licenses are available. `flutter doctor -v` reports only the missing Visual Studio workload, which is not needed for this Android-only app.
- Physical-phone USB verification is intentionally deferred until final debugging, as requested.
- Assumptions: use Riverpod for the planned state management and `sqflite` + `path` for local SQLite storage. Material 3 follows the system light/dark mode.
- Added the initial feature-based folder skeleton, four placeholder tabs, shared app constants, and an MQTT topic builder with the default `ghar` prefix.
- Set Android `compileSdk` to 37 and enabled core-library desugaring as required by `flutter_local_notifications` 23.0.2 and `permission_handler_android`.
- Resolved planned free dependencies: `mqtt_client` 10.14.0, `flutter_riverpod` 3.5.0, `sqflite` 2.4.6, `path` 1.9.1, `shared_preferences` 2.5.6, `fl_chart` 1.3.1, `flutter_local_notifications` 23.0.2, `flutter_foreground_task` 11.0.3, `permission_handler` 13.0.2, `intl` 0.20.3, and `material_ui` 1.11.1.
- `dart format lib test`, `flutter analyze`, and `flutter test` pass.
- `flutter build apk --debug` passes. APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- A physical phone is intentionally not connected yet; final device debugging remains outstanding.

## Not started

- Phase 1 MQTT connection and broker settings.
- Relay control, live monitoring/history, NILM, and alerts.
