## 0. ROLE AND WORKING STYLE

You are a senior Flutter/Dart engineer and mentor. You are helping a 3rd-year ECE student build the **mobile app** for a college mini project. The student is strong in Python and machine learning (TensorFlow, Keras, scikit-learn, FastAPI) but is **new to Flutter and Dart**. Therefore:

- Work **one phase at a time**. Finish a phase, tell me how to run and test it, and wait for my confirmation before starting the next phase.
- Explain Flutter/Dart concepts briefly the first time they appear (widgets, state management, async/streams). Keep explanations short and practical.
- Prefer simple, readable code over clever code. Add comments where the logic is not obvious (especially MQTT handling and the NILM engine).
- Before writing code for a phase, state in 3 to 6 lines what you are about to build and which files you will create or change.
- If something is ambiguous, make a sensible default, state the assumption clearly, and continue. Ask me only when a wrong guess would cost a lot of rework.
- Never invent package APIs. If you are unsure of a package's current API, check its documentation or its `example/` folder first, and tell me which version you used.
- After each phase, give me: (1) the file tree changes, (2) exact commands to run, (3) a short manual test checklist, (4) what is intentionally not done yet.

---

## 1. PROJECT CONTEXT (background you must know)

**Project name:** Ghar (Hindi for "home")

**Full title:** Ghar: Subscription-Free Smart Home Automation Using Non-Intrusive Load Monitoring (NILM)

**What the whole system does:**
A low-cost smart home controller built around one ESP32 unit.
1. It switches **6 AC appliances** (e.g. geyser, fridge, TV, fan, lights) through a 6-channel relay module.
2. One energy meter (**PZEM-004T v3** with a CT coil on the main incoming line) measures the **total** household load (voltage, current, power, energy).
3. Using **event-based NILM**, the system estimates how much each appliance uses *without a separate meter per appliance*. The key idea: because the controller itself switches the relays, it knows exactly when an appliance changes state. It reads the step change in total power at that moment and learns that appliance's typical wattage. This avoids large labelled datasets.
4. A **gas sensor** on the ESP32 detects gas leaks (this is an addition to the original synopsis).
5. Everything works **without a paid subscription** and, on the local network, **without internet**.

**Original synopsis goals (for reference; the app covers only part of this):** hybrid offline/online control, voice control in Hindi/English/Hinglish (extension, NOT in this prompt's scope), user-governed rule engine (timers, auto-off, load limits), single-meter load insight, heavy-use detection, bill estimation, secure remote access, optional Google Home/Alexa integration (NOT in scope).

**Project deadline:** January 2027 (semester mini project, 2 credits). It is a college showcase project; it will **not** be published on the Play Store.

---

## 2. TEAM SPLIT AND SCOPE (very important)

**My part (what you are building):** the **Flutter Android app only**. It must be a real mobile app, **not** a web app.

**Teammate's part (NOT your job, do not build it):**
- ESP32 firmware (relay control, PZEM reading, gas sensor reading, publishing MQTT messages)
- Hardware, wiring, enclosure, electrical safety
- The Mosquitto broker setup on a laptop or Raspberry Pi

**How the two sides connect:** only through the **Mosquitto MQTT broker**. The app and the ESP32 never talk to each other directly. Both connect to the broker as clients. The agreed topics and JSON formats are in Section 4. Treat Section 4 as the **contract**: build the app against it, and keep the topic names configurable in one place so they can be changed quickly if my teammate changes them.

**Because the hardware may not be ready, you must also provide a Python simulator** (Section 9) that behaves like the ESP32 so I can develop and test the app with no hardware.

**Out of scope (do not add unless I ask):** voice control, wake word, rule engine on the device, Firebase or any paid cloud service, user accounts/login backend, iOS support, Play Store publishing, Matter/Google Home/Alexa.

---

## 3. HARD CONSTRAINTS

1. **Cost: Rs 0.** Use only free and open-source tools and packages. No paid APIs, no Firebase, no cloud subscriptions.
2. **Platform:** Flutter (current stable) targeting **Android** (test on a real phone on the same Wi-Fi as the broker; an emulator cannot reach a laptop broker by its normal address).
3. **Language:** Dart. Keep to null-safe, current Dart.
4. **Offline-first:** local control must work with no internet at all (phone and broker on the same Wi-Fi router).
5. **Local storage only:** all history and learned data stay on the phone (SQLite). No external server.
6. **Install method:** `flutter build apk` and install by USB or file sharing. No Play Store.
7. **Safety honesty:** the app must never show a relay state the ESP32 has not confirmed (see Section 5.1).

---

## 4. MQTT CONTRACT (proposed; confirm with teammate)

Broker: Mosquitto, default port 1883 (plain TCP on the local network). The app must let me configure host, port, optional username and password, and optional TLS (port 8883) in Settings.

| Topic | Direction | Payload | Notes |
|---|---|---|---|
| `ghar/relay/<1-6>/set` | app -> ESP32 | `ON` or `OFF` (plain text) | Command. QoS 1. Not retained. |
| `ghar/relay/<1-6>/state` | ESP32 -> app | `ON` or `OFF` (plain text) | **Retained.** The truth about the relay. |
| `ghar/power` | ESP32 -> app | `{"v":230.1,"a":1.2,"w":276.0,"kwh":12.4}` | Total mains reading, about every 1 to 2 seconds. Not retained. |
| `ghar/gas` | ESP32 -> app | `{"leak":false}` (optionally `"ppm":123`) | Publish on change and periodically. Retained is acceptable. |
| `ghar/status` | ESP32 -> app | `online` or `offline` | ESP32 sets an MQTT **last-will** to `offline`; publishes `online` (retained) on connect. |

Rules:
- Put all topic strings in one file (`lib/core/mqtt_topics.dart`) with a configurable prefix (default `ghar`).
- Parse every JSON message defensively: wrong types, missing fields, or invalid JSON must be logged and ignored, never crash the app.
- The app has its own unique MQTT client ID (e.g. `ghar-app-<random>`), keep-alive of about 20 to 30 seconds, and automatic reconnect with backoff.
- On connect, subscribe to `ghar/relay/+/state`, `ghar/power`, `ghar/gas`, `ghar/status`.

---

## 5. FEATURES, IN PHASES

### Phase 0: Environment and skeleton
- Verify the project setup (`flutter doctor` clean, Android toolchain, a real phone with USB debugging).
- Create the Flutter project `ghar_app`. Set up the folder structure from Section 6.
- Add dependencies (Section 7). Set up Material 3 theming with light and dark mode.
- Create a bottom navigation shell with 4 tabs: **Control, Monitor, Insights, Settings**. Screens can be placeholders at this stage.
- Deliverable: app runs on the phone and shows the 4 empty tabs.

### Phase 1: MQTT connection ("hello world")
- Build `MqttService` (a single class that owns the connection) exposing streams/state for: connection status, relay states, power readings, gas status, device online/offline.
- Settings screen: broker host, port, username, password, TLS toggle, topic prefix. Persist with `shared_preferences`.
- Show a connection status chip (Connected / Connecting / Disconnected / Device offline) visible on every screen.
- Test: with MQTT Explorer or the Python simulator, publish to `ghar/relay/1/state` and see it reach the app; press a debug button in the app and see a message arrive on `ghar/relay/1/set`.

### Phase 2: Control screen (core feature)
- Six cards, one per relay, each with: editable name (default Relay 1..6, user may rename e.g. "Geyser"), an icon, a switch, and a state indicator.
- **Command/confirm behaviour (Section 5.1).**
- Appliance names and icons persist locally.
- Optional per-device flag "Protected (never auto-off)", used later by the alerts logic; refrigerator-type devices should be markable as protected.

### Phase 3: Monitor screen
- Live tiles: total power (W), voltage (V), current (A), cumulative energy (kWh).
- A live line chart of the last N minutes of power (use `fl_chart`).
- Store downsampled history in SQLite (for example one row per 10 seconds, plus a daily summary table) so charts survive app restarts. Keep storage bounded (prune raw data older than about 30 days).
- Estimated bill: user sets a per-unit tariff (and optionally slabs) in Settings. Show today and this month's units and estimated cost.

### Phase 4: NILM engine and Insights screen (the main "project" feature)
Implement as a **pure Dart class with no Flutter imports** so it can be unit-tested and, if I later choose, moved to a Python backend. Details in Section 8.
- Insights screen shows: learned wattage per appliance (with confidence), today's estimated energy per appliance, share of total load, and a residual "Other/unknown" bucket.
- Manual wattage override per appliance (user can type the known wattage); manual value takes priority over learned.

### Phase 5: Alerts
- **Gas leak alert (safety-critical):** when `leak` becomes true, raise a high-priority notification and an in-app full-screen alert with a loud, repeating alert until acknowledged. This must work when the app is in the background (Section 5.2).
- **Heavy-use alert:** if an appliance has been ON longer than a user-set duration (for example geyser over 3 hours), notify. Warn only; **never switch anything off automatically** unless the user explicitly enabled that for the device. No default auto-off rules.
- **Over-limit load alert:** if total power exceeds a user-set limit, notify.
- Device-offline alert if `ghar/status` becomes `offline`.
- Notification history list in the app.

### Phase 6 (optional, only if time remains): Timers and hybrid broker
- Simple timers ("TV on for 30 minutes"). Decide with me first whether timers run in the app or on the ESP32 (the ESP32 is more reliable because it works when the phone is away).
- **Hybrid connection:** two broker profiles (Local and Remote). Try Local first; if it fails after a timeout, switch to Remote. The same topics are used on both. Remote may be a free tier of a cloud MQTT broker or a Tailscale address; the app only needs a host/port.

### Phase 7: Polish and report support
- Empty states, error messages, loading states, app icon and name, dark mode check.
- Clean README with setup steps, architecture diagram, MQTT contract, and screenshots checklist.
- Produce a short list of known limitations (honest evaluation: variable loads like refrigerators, manually switched appliances, several similar loads switched together).

### 5.1 Command and confirmation behaviour (rule for all switches)
1. When the user taps a switch, publish `ON`/`OFF` to `.../set`, show a "pending" spinner on that card, and **do not** flip the displayed state.
2. The displayed state changes **only** when `.../state` arrives from the ESP32.
3. If no confirmation arrives within about 3 seconds, show "No response" on that card and let the user retry.
4. If the device is offline (`ghar/status` = `offline`) or the broker is disconnected, disable the switches and say why.

### 5.2 Background behaviour (needed for gas alerts)
- Use an Android **foreground service** (for example `flutter_foreground_task` or `flutter_background_service`) to keep the MQTT connection alive while the app is minimized, with a persistent notification such as "Ghar is monitoring".
- Request `POST_NOTIFICATIONS` (Android 13+) and guide the user to disable battery optimization for the app if required.
- Use a high-importance notification channel for gas alerts.
- Be honest in the README: a phone alert is a **secondary** safety layer. The primary protection (buzzer, cutting the supply) must be implemented by the ESP32 hardware itself.

---

## 6. ARCHITECTURE AND FOLDER STRUCTURE

Use a simple feature-based structure with **Riverpod** for state management (or Provider if you judge it simpler; justify the choice in one line). Keep UI, state, and data layers separate.

```
lib/
  main.dart
  app.dart                      # MaterialApp, theme, navigation shell
  core/
    mqtt_topics.dart            # all topic strings + prefix (single source of truth)
    constants.dart
  data/
    mqtt_service.dart           # connection, subscribe, publish, reconnect, streams
    db.dart                     # SQLite setup (sqflite or drift)
    repositories/
      settings_repository.dart
      history_repository.dart   # power samples, daily summaries
      appliance_repository.dart # names, icons, protected flag, wattage profile
      alert_repository.dart
  domain/
    models/                     # PowerReading, RelayState, Appliance, AlertItem...
    nilm/
      nilm_engine.dart          # pure Dart, no Flutter imports
      nilm_engine_test.dart (in test/)
  features/
    control/                    # screen + widgets + providers
    monitor/
    insights/
    alerts/
    settings/
  services/
    notification_service.dart
    background_service.dart
test/
  nilm_engine_test.dart
  mqtt_parsing_test.dart
tools/
  esp32_simulator.py          # Python fake ESP32 (Section 9)
```

Data flow: `MqttService` -> Riverpod providers (streams) -> UI. Incoming power readings also go to the history repository and to the NILM engine. Relay commands and relay state changes also go to the NILM engine as events.

---

## 7. SUGGESTED PACKAGES (all free; verify current versions and APIs)

- `mqtt_client` (MQTT over TCP; use its `example/` folder as the primary reference)
- `flutter_riverpod` (state management)
- `sqflite` + `path` (or `drift`) for local SQLite storage
- `shared_preferences` (settings)
- `fl_chart` (charts)
- `flutter_local_notifications` (alerts; no cloud push)
- `flutter_foreground_task` or `flutter_background_service` (background MQTT)
- `permission_handler` (notification permission, battery optimization guidance)
- `intl` (date and currency formatting)
- Dev: `flutter_test`, `mocktail` (optional)

Do not add Firebase, any analytics SDK, or any package requiring an API key.

---

## 8. NILM ENGINE SPECIFICATION (event-based, switch-aware)

Goal: learn each appliance's typical power draw from the step change in total power at the moment it is switched, then estimate per-appliance energy.

**Inputs**
- Stream of total power readings `(timestamp, watts)`.
- Stream of relay events `(timestamp, relayIndex, newState)`, where a relay event is registered when a **confirmed** `state` message arrives (and remember the command time).

**Event handling algorithm**
1. Keep a rolling buffer of recent power samples (at least the last 30 seconds).
2. On a confirmed relay change at time `t`:
   - `baseline` = median of power samples in the window `[t - 6s, t - 1s]`.
   - Wait for the load to settle (about 4 to 5 seconds after `t`; ignore the first 1 to 2 seconds to skip inrush spikes), then `after` = median of samples in `[t + 3s, t + 8s]`.
   - `delta = after - baseline`. For ON events expect `delta > 0`; for OFF events expect `delta < 0` (use the absolute value).
3. **Reject the sample** (do not learn) if: the baseline is unstable (high standard deviation), the delta is tiny (below a noise threshold, e.g. under 5 to 10 W, configurable), or **another relay changed within the same window** (confounded event). Log why it was rejected.
4. For each accepted sample, update that relay's wattage estimate using a **robust statistic** (median of the last K accepted samples, with simple outlier rejection). Track the sample count and spread, and expose a **confidence** value (low with 1 sample, higher with more consistent samples).
5. A user-entered manual wattage overrides the learned value.

**Energy estimation**
- Track ON intervals per relay from confirmed states (handle app restarts by reconstructing from the latest retained states and stored events).
- Estimated appliance energy = wattage x ON time. Compare the sum of appliance estimates with the measured total energy; show the difference as **"Other/unknown"** (covers refrigerators cycling, appliances switched manually outside Ghar, etc.).
- Treat devices marked "protected" or known variable loads (like a fridge) as low-confidence and say so in the UI.

**Heavy-use detection:** based on ON duration and learned/manual wattage, per Section 5 Phase 5.

**Must-have unit tests** (in `test/nilm_engine_test.dart`), using synthetic data:
- Clean ON event learns the right wattage; OFF event agrees.
- Noisy baseline within tolerance still learns correctly.
- Confounded events (two relays within the window) are rejected.
- Tiny delta below threshold is rejected.
- Manual wattage overrides learned wattage.
- Energy estimate matches a hand-calculated example.

Keep the engine deterministic and free of Flutter, MQTT, and database imports; pass data in through method calls so it can be tested and, if needed, reused in a Python service later.

---

## 9. PYTHON ESP32 SIMULATOR (build in Phase 1, extend as needed)

Create `tools/esp32_simulator.py` using `paho-mqtt`. It must behave like the ESP32 according to the Section 4 contract:
- Connect with a last-will on `ghar/status` = `offline`; publish `online` (retained) after connecting.
- Subscribe to `ghar/relay/+/set`. On a command, wait a short random delay (100 to 500 ms), update an internal state, and publish the new state to `ghar/relay/N/state` (**retained**).
- Hold wattages for the 6 appliances (for example geyser 2000 W, fridge 150 W, TV 100 W, fan 60 W, light 20 W, light 20 W), plus a small random noise.
- Publish `ghar/power` every 1 to 2 seconds with `w` = sum of appliances currently ON + noise + a baseline, and consistent `v`, `a` (a = w / v), and an increasing `kwh`.
- Optional flags/keys: a command-line option or keyboard command to **trigger a gas leak** (`ghar/gas` `{"leak":true}`) and clear it; an option to **simulate going offline**; an option to **ignore commands** (to test the "No response" case); a variable fridge-like load that cycles on and off by itself (to test the NILM residual).

Include a short README on how to run Mosquitto locally, run the simulator, and use MQTT Explorer.

---

## 10. UI/UX GUIDELINES

- Material 3, clean, large touch targets, readable at a glance. Light and dark mode.
- Control screen: 2-column grid or list of 6 cards; each card shows the name, the ON/OFF state, and a switch. Show pending, no-response, and offline states clearly.
- Monitor screen: big total-watts number, a live chart, and kWh/bill tiles.
- Insights: a pie or bar breakdown by appliance plus "Other/unknown", with confidence labels and a button to enter a manual wattage.
- Always show a small connection status chip.
- Gas alert: bold, red, full-screen, with an "I understand / acknowledge" button; do not auto-dismiss.
- Hindi/English: UI in English for now, but keep all user-facing strings in one place (a constants file or `intl`/ARB) so a Hindi translation can be added later.

---

## 11. REFERENCE PROJECTS TO LEARN FROM (this is a college showcase project, not a published product)

You may study existing open-source code and adapt patterns from it. This is a non-commercial academic project that will not be published. Still: **read each repository's license file before copying code, keep copied snippets small, rewrite them to fit this codebase, and list every borrowed source in the README under "Acknowledgements/References".** Do not copy large chunks verbatim. Verify each link or package name exists and is current before relying on it (search GitHub if a link has moved).

Useful places to learn specific parts:
1. **`mqtt_client` package (by shamblett), its `example/` folder:** the best reference for connecting, subscribing, publishing, QoS, last-will, and auto-reconnect in Dart.
2. **`fl_chart` package, its example app:** line chart and pie chart examples for the Monitor and Insights screens.
3. **`flutter_local_notifications` package, its `example/` app:** notification channels, high-importance alerts, and permissions on Android.
4. **`flutter_foreground_task` or `flutter_background_service` examples:** keeping a connection alive in the background on Android.
5. **Home Assistant Companion app for Android (`home-assistant/android` on GitHub; Kotlin, not Flutter):** a mature smart-home app. Use it only as a **UX reference** (how switch cards, entity state, offline/unavailable states, and alerts are presented), not for code.
6. **NILMTK (`nilmtk/nilmtk`, Python):** the standard open-source NILM toolkit. Use it only as a **conceptual reference** for event detection and evaluation metrics (such as mean absolute error of estimated wattage), not for code reuse.
7. **Tasmota (smart-switch firmware) and its MQTT topic conventions:** useful for how real devices name their `cmnd`/`stat`/`tele` topics, retained states, and last-will availability. Our contract in Section 4 follows the same ideas in simpler form.
8. **GitHub search ideas** for Flutter smart-home UI patterns: search for `flutter mqtt smart home`, `flutter mqtt relay switch`, `flutter iot dashboard`. Pick projects with a clear license and recent activity, and treat them as inspiration for layouts and state handling.

Cite what you used in `README.md`.

---

## 12. DELIVERABLES

1. A working Flutter Android app (Phases 0 to 5 are the **minimum viable project**; Phase 6 and 7 as time allows).
2. `tools/esp32_simulator.py` and a README for running it.
3. Unit tests for the NILM engine and for MQTT message parsing.
4. `README.md`: overview, architecture diagram (text or Mermaid), setup and run steps, the MQTT contract, background-service and permissions notes, known limitations, references/acknowledgements.
5. A short **evaluation checklist** I can fill in for the report: command latency (tap to confirmed state), NILM wattage error versus a reference measurement, heavy-use alert correctness (correct versus missed/false), behaviour when the broker or device goes offline, gas alert delivery in the foreground and background.

---

## 13. DEFINITION OF DONE (minimum viable project)

- App installs from an APK on a real Android phone and connects to Mosquitto over the local Wi-Fi.
- Six switches control relays through MQTT, and the UI only changes after the ESP32 confirms.
- Live total power, voltage, current, and kWh are displayed, with a chart and a saved history.
- NILM learns appliance wattages from switch events and shows estimated per-appliance energy plus "Other/unknown"; manual override works.
- Gas leak and heavy-use alerts fire as notifications, including when the app is in the background.
- Everything works with no internet and at no cost.
- Works against the Python simulator now, and against the real ESP32 later **with only broker/topic settings changed**.

---

## 14. START NOW

Begin with **Phase 0**. First list the assumptions you are making (Flutter version, state-management choice, database choice), then give me the exact commands and file changes for Phase 0, and stop for my confirmation before Phase 1.
