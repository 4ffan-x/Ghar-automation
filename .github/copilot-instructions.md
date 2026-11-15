This is the Ghar Flutter Android app (not web). Full spec: PROJECT.md. Read it before any task.
- Never edit PROJECT.md. Record progress, assumptions and package versions in PROGRESS.md after every phase.
- Work one phase at a time. After each phase give: file tree changes, run commands, manual test checklist, what's not done. Then stop and wait for my confirmation.
- Before coding a phase, state in 3-6 lines what you'll build and which files change.
- The MQTT topics in PROJECT.md Section 4 are a contract with the ESP32 firmware. Don't change them. Keep all topic strings in lib/core/mqtt_topics.dart.
- Never show a relay state the ESP32 hasn't confirmed.
- Don't invent package APIs. Check the package docs or example/ folder and tell me the version used.
- Don't add anything listed as out of scope in PROJECT.md.
- I'm new to Flutter/Dart. Use simple readable code, comment non-obvious logic (MQTT, NILM), and explain new concepts briefly the first time.
- Free and open-source packages only.
