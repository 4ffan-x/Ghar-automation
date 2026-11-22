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

## Phase 3 — Monitor, saved history, and bill estimate

- Added live power, voltage, current, and cumulative-kWh tiles, plus a `fl_chart` graph showing saved samples from the last 30 minutes.
- Added local SQLite storage for chart samples (at most one per 10 seconds, with raw samples older than 30 days pruned), daily energy summaries, and a cumulative-meter cursor. Energy deltas are recorded on every received reading; a meter reset does not create negative usage.
- Added a persisted per-kWh tariff setting and today/month energy and linear bill estimates. Slabs, taxes, and fixed charges are not included.
- The first cumulative meter reading is used only as a baseline, so consumption before the app records its first reading is not estimated. Daily energy summaries remain stored; chart samples are limited to the last 30 days and the Monitor chart displays the last 30 minutes.
- Updated `README.md` with simulator steps to exercise the Monitor, history across app restarts, and a tariff estimate, plus a `mosquitto_pub` sequence for testing without the simulator.
- Packages used: `sqflite` 2.4.6, `fl_chart` 1.3.1, and test-only `sqflite_common_ffi` 2.4.7. MQTT topic strings and `MqttService` behavior were not changed.
- Verified: `dart format lib test`, `flutter analyze`, `flutter test --reporter expanded` (15 tests), `flutter build apk --debug`, and `git diff --check` pass. Android debug APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- Live Mosquitto and physical-phone testing remain outstanding.

## Phase 4 — NILM engine and Insights

- Added a pure-Dart NILM engine with no Flutter, MQTT, or database imports. It retains a rolling 30-second power buffer and evaluates relay wattage only after a confirmed state transition.
- Learning compares median power in `t - 6s` to `t - 1s` with `t + 3s` to `t + 8s`. It rejects unstable baselines (standard deviation above 15 W), steps below 8 W or in the wrong direction, insufficient window samples, transitions confounded by another nearby relay change, and large outliers. Accepted values use the median of the latest seven samples; sample count and spread inform confidence.
- Added SQLite persistence for power-window samples, confirmed relay events, and learned wattage samples, including a database v1-to-v2 migration. Confirmed relay intervals and learned profiles are restored after app restarts. Manual wattage overrides are saved locally with existing appliance preferences and take priority over learned values.
- Replaced the Insights placeholder with daily wattage/confidence, estimated kWh and measured-total shares per appliance, a manual-override editor, and an **Other / unknown** residual. If appliance estimates exceed the meter total, the mismatch is shown instead of hidden. Protected and fridge-like loads are called out as low confidence.
- Updated `README.md` with simulator learning steps, `--variable-fridge` testing, synthetic test commands, and a simple viva explanation. No package additions; the project continues using `sqflite` 2.4.6 and `shared_preferences` 2.5.6. MQTT topic strings and `MqttService` behavior were not changed.
- Verified: `dart format lib test`, `flutter analyze`, `flutter test --reporter expanded` (25 tests), `flutter build apk --debug`, and `git diff --check` pass. APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- Live broker and physical-phone testing remain pending. A relay change missed while the broker/app is disconnected has no exact timestamp; the retained state restores the current state, but energy attribution around that unseen transition is approximate. The learner is an estimate, not individual appliance measurement.

## Not started

- Phase 5: alerts.
- Optional Phase 6: timers and hybrid broker.
