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

## Phase 1 — MQTT connection

- Added broker settings for host, port, optional username/password, TLS, and topic prefix, persisted locally with `shared_preferences` 2.5.6.
- Added `MqttService` using `mqtt_client` 10.14.0. It uses a unique app client ID, a 25-second keep-alive, subscriptions for relay state/power/gas/device status, and reconnect attempts with exponential backoff capped at 30 seconds.
- Added defensive message parsing and typed streams for confirmed relay states, power readings, gas status, broker connection, and device availability. Invalid messages are logged and ignored.
- The broker status chip appears in the shared app bar on every tab. Settings has test ON/OFF command buttons and shows relay state only after a `.../state` message arrives; commands do not change the displayed confirmation.
- Added Android `INTERNET` and `ACCESS_NETWORK_STATE` permissions.
- Added `tools/esp32_simulator.py`, pinned `paho-mqtt` 2.1.0 in `tools/requirements.txt`, and documented Windows Mosquitto/firewall/Wi-Fi setup plus simulator and manual publish/subscribe steps in `README.md`.
- Verified: `dart format lib test`, `flutter analyze`, `flutter test`, `flutter build apk --debug`, `python -m py_compile tools\\esp32_simulator.py`, and simulator `--help` all pass. Installed/tested the simulator against `paho-mqtt` 2.1.0.
- Live Mosquitto/phone testing remains outstanding; complete it when a broker and phone are available.

## Phase 2 — Confirmed relay control

- Added six relay cards with confirmed state labels, confirmation-gated switches, pending spinners, 3-second no-response feedback, and retry support.
- Relay switches are not shown until an ESP32 `.../state` value is received. Existing confirmed values are not changed optimistically when commands are sent. Controls are disabled unless the broker is connected, the device has reported online, and that relay has a confirmed state.
- Added persistent appliance names, six selectable built-in icons, and a per-appliance "Protected (never auto-off)" preference using `shared_preferences` 2.5.6. Protection is stored as a future preference only; no automatic switching behavior was added.
- Reused the existing `MqttService.publishTestRelayCommand` path without changing `MqttService` behavior or MQTT topic strings.
- Updated `README.md` with simulator and `mosquitto_pub`/`mosquitto_sub` relay-control test steps.
- Verified: `dart format lib test`, `flutter analyze`, `flutter test --reporter expanded`, `flutter build apk --debug`, and `git diff --check` pass. Tests cover unknown relay state, command confirmation, timeout/late confirmation, and appliance name/icon/protection persistence.
- The Phase 1 live Mosquitto and physical-phone test is still pending. Phase 2 has not yet been verified against a live broker or phone.

## Not started

- Phase 3 live monitor, chart, stored power history, and estimated bill.
- Phases 4–5: NILM insights and alerts.
