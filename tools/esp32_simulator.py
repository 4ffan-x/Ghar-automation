#!/usr/bin/env python3
"""A small MQTT fake ESP32 for testing the Ghar app without hardware."""

import argparse
import json
import random
import re
import threading
import time

import paho.mqtt.client as mqtt


APPLIANCE_WATTS = [2000, 150, 100, 60, 20, 20]
BASELINE_WATTS = 8
VOLTAGE = 230.0


class Esp32Simulator:
    def __init__(self, args):
        self.args = args
        self.prefix = args.prefix
        self.states = [False] * 6
        self.gas_leak = args.gas_leak
        self.device_online = not args.simulate_offline
        self.energy_kwh = 0.0
        self.last_power_update = time.monotonic()
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.relay_command = re.compile(
            rf"^{re.escape(self.prefix)}/relay/([1-6])/set$"
        )

        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=f"ghar-simulator-{random.randrange(1 << 32):08x}",
            protocol=mqtt.MQTTv311,
        )
        self.client.will_set(
            f"{self.prefix}/status",
            payload="offline",
            qos=1,
            retain=True,
        )
        if args.username:
            self.client.username_pw_set(args.username, args.password)
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            print(f"Broker connection rejected: {reason_code}")
            return

        print(f"Connected to {self.args.host}:{self.args.port}.")
        client.subscribe(f"{self.prefix}/relay/+/set", qos=1)
        self._publish(
            f"{self.prefix}/status",
            "online" if self.device_online else "offline",
            retain=True,
        )
        self._publish(
            f"{self.prefix}/gas",
            json.dumps({"leak": self.gas_leak}),
            retain=True,
        )
        for relay, is_on in enumerate(self.states, start=1):
            self._publish(
                f"{self.prefix}/relay/{relay}/state",
                "ON" if is_on else "OFF",
                retain=True,
            )

    def _on_message(self, client, userdata, message):
        if self.args.ignore_commands:
            print(f"Ignoring command on {message.topic}.")
            return
        if not self.device_online:
            print("Device is marked offline; ignoring relay command.")
            return

        match = self.relay_command.fullmatch(message.topic)
        if match is None:
            return
        try:
            requested_state = message.payload.decode("utf-8").strip().upper()
        except UnicodeDecodeError:
            print(f"Ignoring non-text command on {message.topic}.")
            return
        if requested_state not in ("ON", "OFF"):
            print(f"Ignoring invalid relay command: {requested_state!r}")
            return

        relay = int(match.group(1))
        threading.Thread(
            target=self._confirm_relay_command,
            args=(relay, requested_state),
            daemon=True,
        ).start()

    def _confirm_relay_command(self, relay, requested_state):
        time.sleep(random.uniform(0.1, 0.5))
        is_on = requested_state == "ON"
        with self.lock:
            self.states[relay - 1] = is_on
        self._publish(
            f"{self.prefix}/relay/{relay}/state",
            requested_state,
            retain=True,
        )
        print(f"Relay {relay} confirmed {requested_state}.")

    def _publish(self, topic, payload, retain=False):
        self.client.publish(topic, payload, qos=1, retain=retain)

    def publish_power_reading(self):
        with self.lock:
            active_watts = sum(
                watts for watts, is_on in zip(APPLIANCE_WATTS, self.states)
                if is_on
            )

        if self.args.variable_fridge and int(time.monotonic() / 15) % 2:
            active_watts += 150

        now = time.monotonic()
        elapsed = now - self.last_power_update
        self.last_power_update = now
        watts = max(
            0.0,
            BASELINE_WATTS + active_watts + random.uniform(-2.0, 2.0),
        )
        self.energy_kwh += watts * elapsed / 3_600_000
        reading = {
            "v": VOLTAGE,
            "a": round(watts / VOLTAGE, 3),
            "w": round(watts, 1),
            "kwh": round(self.energy_kwh, 5),
        }
        self._publish(f"{self.prefix}/power", json.dumps(reading))

    def run(self):
        self.client.connect(self.args.host, self.args.port, keepalive=25)
        self.client.loop_start()
        print("Commands: gas-on, gas-off, device-offline, device-online, quit")
        threading.Thread(target=self._read_console_commands, daemon=True).start()

        try:
            while not self.stop_event.wait(random.uniform(1.0, 2.0)):
                if self.device_online:
                    self.publish_power_reading()
        except KeyboardInterrupt:
            pass
        finally:
            self.stop_event.set()
            self._publish(f"{self.prefix}/status", "offline", retain=True)
            self.client.disconnect()
            self.client.loop_stop()
            print("Simulator stopped.")

    def _read_console_commands(self):
        while not self.stop_event.is_set():
            try:
                command = input("> ").strip().lower()
            except EOFError:
                self.stop_event.set()
                return
            self._handle_console_command(command)

    def _handle_console_command(self, command):
        if command == "gas-on":
            self.gas_leak = True
            self._publish(
                f"{self.prefix}/gas",
                json.dumps({"leak": True, "ppm": 123}),
                retain=True,
            )
        elif command == "gas-off":
            self.gas_leak = False
            self._publish(
                f"{self.prefix}/gas",
                json.dumps({"leak": False, "ppm": 0}),
                retain=True,
            )
        elif command == "device-offline":
            self.device_online = False
            self._publish(f"{self.prefix}/status", "offline", retain=True)
        elif command == "device-online":
            self.device_online = True
            self._publish(f"{self.prefix}/status", "online", retain=True)
        elif command in ("quit", "exit", "q"):
            self.stop_event.set()
        elif command:
            print("Unknown command.")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", help="MQTT broker host")
    parser.add_argument("--port", type=int, default=1883, help="MQTT broker port")
    parser.add_argument("--username", default="", help="Optional MQTT username")
    parser.add_argument("--password", default="", help="Optional MQTT password")
    parser.add_argument("--prefix", default="ghar", help="MQTT topic prefix")
    parser.add_argument(
        "--ignore-commands",
        action="store_true",
        help="Ignore relay commands to test the app's no-response handling later",
    )
    parser.add_argument(
        "--gas-leak",
        action="store_true",
        help="Start with the gas leak flag set",
    )
    parser.add_argument(
        "--simulate-offline",
        action="store_true",
        help="Start with the simulated ESP32 marked offline",
    )
    parser.add_argument(
        "--variable-fridge",
        action="store_true",
        help="Add an independent cycling 150 W load to total power",
    )
    args = parser.parse_args()
    if not args.prefix or any(char in args.prefix for char in "/+# \t"):
        parser.error("--prefix must be one MQTT topic segment.")
    return args


if __name__ == "__main__":
    Esp32Simulator(parse_args()).run()
