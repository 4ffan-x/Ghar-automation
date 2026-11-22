# Ghar

Ghar is an Android Flutter app for local smart-home monitoring and control. This
document includes MQTT setup plus simulator guidance for the Monitor and NILM
Insights features.

## Run the Android app

From the repository root:

```powershell
flutter pub get
flutter run -d <android-device-id>
```

In the app, open **Settings**, enter the broker host and port, then select
**Save and connect**. For a local Mosquitto broker, use the Windows PC's
Wi-Fi IPv4 address, port `1883`, TLS off, and topic prefix `ghar`.

## Test with Mosquitto on a Windows PC

### 1. Install Mosquitto

Download and install the free Mosquitto broker and client command-line tools
from [mosquitto.org/download](https://mosquitto.org/download/). Keep the
installer's default location (`C:\Program Files\mosquitto`) or adjust the
commands below to match your installation.

### 2. Create a LAN-only test configuration

Use a trusted private Wi-Fi network. In PowerShell, create a small config
directory and file:

```powershell
New-Item -ItemType Directory -Force C:\mosquitto\data | Out-Null
@'
listener 1883 0.0.0.0
allow_anonymous true
persistence true
persistence_location C:\mosquitto\data\
log_dest stdout
'@ | Set-Content -Encoding ascii C:\mosquitto\mosquitto-local.conf
```

This temporary configuration allows unauthenticated MQTT clients on the LAN.
Do not use it on a public/untrusted network, do not port-forward port 1883, and
do not expose the broker directly to the internet.

### 3. Allow the private LAN through Windows Firewall

In an **Administrator PowerShell** window, first check the Wi-Fi network
profile:

```powershell
Get-NetConnectionProfile
```

If the trusted home Wi-Fi is categorized as `Public`, change only that Wi-Fi
interface to `Private`. Use its interface index from the output:

```powershell
Set-NetConnectionProfile -InterfaceIndex <wifi-interface-index> -NetworkCategory Private
```

Then add a private-profile firewall rule limited to local-subnet clients:

```powershell
New-NetFirewallRule -DisplayName "Mosquitto MQTT 1883 (Private LAN)" -Direction Inbound -Protocol TCP -LocalPort 1883 -Action Allow -Profile Private -RemoteAddress LocalSubnet
```

### 4. Start the broker and find the PC's Wi-Fi IP

If the Mosquitto Windows service is already running, stop it first in
**Services** (or with `Stop-Service mosquitto` in Administrator PowerShell) so
it does not already occupy port 1883. Then open a regular PowerShell window:

```powershell
& 'C:\Program Files\mosquitto\mosquitto.exe' -c 'C:\mosquitto\mosquitto-local.conf' -v
```

Leave that window open. In another window run `ipconfig` and note the **IPv4
Address** under the active **Wireless LAN adapter Wi-Fi**, for example
`192.168.1.25`. Do not use `127.0.0.1` in the phone app: that address refers to
the phone itself.

Connect the Android phone to the same Wi-Fi network. Avoid a guest Wi-Fi that
blocks device-to-device traffic; temporarily disable VPN/mobile-data routing if
the phone cannot reach the PC. In **Settings** set:

- Broker host: the PC's Wi-Fi IPv4 address (for example `192.168.1.25`)
- Port: `1883`
- Username/password: blank for this private test configuration
- TLS: off
- Topic prefix: `ghar`

Tap **Save and connect**. The app should show **Connected** in the top status
chip. The chip changes to **Device offline** only after it receives
`ghar/status` with payload `offline`.

### 5. Confirm messages both ways without an ESP32

Install the Mosquitto client tools if they were not selected during broker
installation. Open a second PowerShell window and subscribe to app commands:

```powershell
& 'C:\Program Files\mosquitto\mosquitto_sub.exe' -h 127.0.0.1 -t 'ghar/relay/1/set' -v
```

In the app's Settings **Connection test** panel, tap **Send test ON**. The
PowerShell window should show `ghar/relay/1/set ON`. Tap **Send test OFF** to
see `OFF`. These are test commands only; sending them does not change the
app's displayed relay state.

Open another PowerShell window to publish ESP32-style confirmed messages:

```powershell
& 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/relay/1/state' -m ON -r
& 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/status' -m online -r
& 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/power' -m '{"v":230.1,"a":1.2,"w":276.0,"kwh":12.4}'
& 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/gas' -m '{"leak":false}'
```

The app's test panel should show Relay 1 as `ON`, a received power reading, and
gas as clear. Publish the confirmed state as `OFF` to verify it changes only
when the state topic message arrives:

```powershell
& 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/relay/1/state' -m OFF -r
```

For the Android app, continue using the PC's Wi-Fi IPv4 address in Settings;
`127.0.0.1` above is correct only for command-line clients running on the PC.

## Run the Python ESP32 simulator

The simulator publishes retained relay states and device availability, sends
power readings, and applies relay commands after a short delay. It also
supports gas and offline test commands.

From the repository root, create a separate Windows virtual environment and
install its single open-source dependency:

```powershell
py -m venv C:\ghar-simulator-venv
C:\ghar-simulator-venv\Scripts\python.exe -m pip install -r tools\requirements.txt
C:\ghar-simulator-venv\Scripts\python.exe tools\esp32_simulator.py --host 127.0.0.1
```

Keep the Mosquitto broker running. Configure the phone app with the PC's Wi-Fi
IPv4 address as described above. In the simulator console, type:

- `gas-on` / `gas-off` to publish gas status
- `device-offline` / `device-online` to publish device availability
- `quit` to stop the simulator cleanly

Optional simulator flags include `--ignore-commands`, `--gas-leak`,
`--simulate-offline`, and `--variable-fridge`. Use `--help` to see all options.
For example:

```powershell
C:\ghar-simulator-venv\Scripts\python.exe tools\esp32_simulator.py --host 127.0.0.1 --variable-fridge
```

### Test Phase 2 relay cards without an ESP32

With Mosquitto running and the phone app connected, start the simulator as
above. Open **Control**. The simulator publishes retained initial state and
`online` status, so relay cards become ready. Tap a switch: the card shows a
pending spinner and keeps its old confirmed state until the simulator publishes
the new retained `ghar/relay/N/state` confirmation. The simulator responds to
commands after a short delay.

To test the app against Mosquitto without running the simulator, use separate
PowerShell windows:

1. Subscribe to commands sent from the app:

   ```powershell
   & 'C:\Program Files\mosquitto\mosquitto_sub.exe' -h 127.0.0.1 -t 'ghar/relay/+/set' -v
   ```

2. Publish device online and initial relay 1 state (repeat for any relay you
   want to control):

   ```powershell
   & 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/status' -m online -r
   & 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/relay/1/state' -m OFF -r
   ```

3. In **Control**, switch Relay 1 on. `mosquitto_sub` should show the `ON`
   command; the displayed state must remain `OFF` and the spinner should
   appear. The app must not update to `ON` until you publish the confirmation:

   ```powershell
   & 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/relay/1/state' -m ON -r
   ```

4. To check the timeout, switch it off and do not publish an OFF confirmation.
   After about 3 seconds, the card should show **No response** and allow retry.
   To test the offline guard, publish `offline` to `ghar/status`; relay
   switches should be disabled.

As in the previous test, use the PC's Wi-Fi IPv4 address in the phone app;
`127.0.0.1` is only for commands run on the PC.

## Test Phase 3 Monitor, history, and bill estimate

The Monitor screen uses the existing Mosquitto broker and simulator setup
above. Start the broker, then run the simulator in a separate PowerShell
window:

```powershell
C:\ghar-simulator-venv\Scripts\python.exe tools\esp32_simulator.py --host 127.0.0.1
```

In the Android app, connect to the broker using the PC's Wi-Fi IPv4 address,
then:

1. In **Settings**, enter the per-unit tariff and tap **Save tariff**. For a
   short demo, a temporarily high test rate (for example, Rs 1000/kWh) makes
   the estimate easier to see; restore the actual rate afterwards.
2. In **Control**, switch Relay 1 on. The simulator confirms the change and
   models Relay 1 as a 2000 W load, so energy accumulates faster than at idle.
3. Open **Monitor**. Voltage, current, power, and cumulative kWh update as
   readings arrive. After at least 10 seconds, the chart should contain saved
   samples (the app stores at most one sample per 10 seconds).
4. Leave it running for a minute or two to see today's/month's kWh and the
   corresponding tariff-based estimate increase. The simulator's cumulative
   meter begins at zero; the app uses the first reading it receives only as a
   baseline, so consumption before that reading is not included.
5. Stop and reopen the app while leaving Mosquitto and the simulator running.
   The recent chart history and energy totals should still be present. The
   chart shows the last 30 minutes; older raw samples are pruned, while daily
   energy summaries remain stored locally.

To test without the simulator, leave Mosquitto and the app connected, stop the
simulator, and publish readings from a PowerShell window on the PC. The first
reading establishes a cumulative-meter baseline; publish the next reading at
least 10 seconds later to add a chart sample and energy delta:

```powershell
& 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/power' -m '{"v":230.0,"a":1.0,"w":230.0,"kwh":10.000}'
# Wait at least 10 seconds.
& 'C:\Program Files\mosquitto\mosquitto_pub.exe' -h 127.0.0.1 -t 'ghar/power' -m '{"v":231.0,"a":2.0,"w":462.0,"kwh":10.500}'
```

The Monitor should show the newer live values and 0.500 kWh added to today's
and this month's energy, multiplied by the saved tariff. Publish another
reading with a higher `kwh` value after 10 seconds to add another saved chart
sample. The estimates use a single per-kWh rate; utility slabs, taxes, and
fixed charges are not included.

## Test Phase 4 NILM Insights

The NILM learner runs locally in the app. It uses power readings and confirmed
relay-state changes; tapping a switch alone is not treated as an event. Start
Mosquitto and the simulator as described above, connect the app, and use
**Control**:

1. Leave a relay **OFF** and wait at least 8 seconds so the app has a stable
   baseline.
2. Turn that relay **ON** and wait at least 10 seconds for the simulator's
   confirmed state and settled power readings. Avoid changing another relay
   around the same time.
3. Optionally turn the relay **OFF**, then wait another 10 seconds. Each clean
   ON or OFF transition is a separate learning opportunity.
4. Open **Insights**. The typical wattage should appear after a clean event,
   along with its sample count/confidence. Energy is estimated from wattage
   times the duration the confirmed relay has been ON. No samples means the
   app shows **Not learned yet** rather than inventing a wattage.
5. To test an override, select **Set wattage override**, enter a known value
   (for example `2000` for the simulator's geyser relay), and save. The manual
   value takes priority over future learned values. Clear it from the same
   dialog to return to the learned estimate.
6. To test a rejected/confounded event, change another relay within 8 seconds
   before or after the first relay transition. The event should not add a
   wattage sample; the reason is written to the app debug log.

For the cycling-load check, stop the default simulator and restart it with:

```powershell
C:\ghar-simulator-venv\Scripts\python.exe tools\esp32_simulator.py --host 127.0.0.1 --variable-fridge
```

This option adds an independent 150 W load that cycles roughly every 15
seconds; it is not controlled by a relay. Insights should therefore leave the
unexplained meter energy in **Other / unknown** rather than falsely assigning
it to a relay. If an actual appliance is a fridge, set its icon to **Fridge**
in **Control**; protected and fridge-like appliances are explicitly marked
low confidence because their load can vary without a relay event.

### NILM in simple terms (viva explanation)

The app does not have a separate meter on each appliance. When the ESP32
confirms a relay change, the app takes the median total power from 6 to 1
seconds before the change, then compares it with the median from 3 to 8
seconds after the change (after startup spikes have settled). The difference
is treated as that appliance's wattage. A noisy baseline, a very small change,
or another relay changing nearby makes the app reject that sample. Over time,
it keeps a median of recent accepted wattage samples and reports confidence
from the number and consistency of samples.

For today's use, the estimate is **wattage × confirmed ON time ÷ 1000** to get
kWh. The app compares the sum with the meter's measured energy. The remaining
positive energy is shown as **Other / unknown**; if appliance estimates exceed
the meter, the app shows that mismatch instead of hiding it. This is an
estimate, not per-appliance measurement, and independently cycling loads,
manual switching, and simultaneous appliance changes can reduce accuracy.

Run the deterministic synthetic-data tests without a phone or broker:

```powershell
flutter test test\nilm_engine_test.dart test\nilm_repository_test.dart
```

Confirmed events are saved locally and replayed after an app restart. If a
relay changes while the app or broker is disconnected, the retained state can
restore its current ON/OFF status, but the exact time of the unseen change is
unknown; energy for that boundary is therefore approximate.

## MQTT package

The app currently uses `mqtt_client` 10.14.0. Its connection, subscription,
publish, and TLS configuration follows the package's included
`example/mqtt_server_client.dart`, `example/mqtt_server_client_secure.dart`,
and `example/mqtt_server_client_autoreconnect.dart`.