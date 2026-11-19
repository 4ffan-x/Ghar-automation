# Ghar

Ghar is an Android Flutter app for local smart-home monitoring and control. This
document covers Phase 1: MQTT broker setup and testing without the ESP32.

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

## MQTT package

The app currently uses `mqtt_client` 10.14.0. Its connection, subscription,
publish, and TLS configuration follows the package's included
`example/mqtt_server_client.dart`, `example/mqtt_server_client_secure.dart`,
and `example/mqtt_server_client_autoreconnect.dart`.