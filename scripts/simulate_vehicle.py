#!/usr/bin/env python
"""
Vehicle location simulator for Sarthi.

Simulates a vehicle moving around Jhapa, Nepal by performing a random walk
and pushing location updates to the API every 4 seconds.

Usage:
    python scripts/simulate_vehicle.py <vehicle_id>
    python scripts/simulate_vehicle.py 1
    python scripts/simulate_vehicle.py 1 --interval 2  # faster updates
"""

import argparse
import random
import sys
import time

import requests

# --- Configuration ---
API_BASE = 'http://localhost:8000/api'

# Starting point: near Birtamode, Jhapa, Nepal
START_LAT = 26.6468
START_LNG = 87.8942

# How far the vehicle moves per step (in degrees).
# ~0.0005° ≈ 55 meters — realistic for urban vehicle movement at ~50 km/h
STEP_SIZE = 0.0005


def simulate(vehicle_id: int, interval: float = 4.0):
    """Run infinite random-walk simulation for the given vehicle."""
    url = f'{API_BASE}/vehicles/{vehicle_id}/update-location/'
    lat, lng = START_LAT, START_LNG

    print(f'🚗 Simulator started for vehicle {vehicle_id}')
    print(f'   Endpoint : {url}')
    print(f'   Start    : ({lat:.6f}, {lng:.6f})')
    print(f'   Interval : {interval}s')
    print(f'   Press Ctrl+C to stop\n')

    step = 0
    while True:
        # Random walk: nudge lat/lng by a small random amount
        lat += random.uniform(-STEP_SIZE, STEP_SIZE)
        lng += random.uniform(-STEP_SIZE, STEP_SIZE)

        # Clamp to valid ranges (shouldn't matter in practice for Nepal)
        lat = max(-90.0, min(90.0, lat))
        lng = max(-180.0, min(180.0, lng))

        payload = {'lat': round(lat, 6), 'lng': round(lng, 6)}

        try:
            resp = requests.post(url, json=payload, timeout=5)
            if resp.status_code == 200:
                data = resp.json()
                step += 1
                print(
                    f'  [{step:>4}] ✅ {data["name"]} → '
                    f'({payload["lat"]:.6f}, {payload["lng"]:.6f})'
                )
            else:
                print(f'  [{step:>4}] ❌ HTTP {resp.status_code}: {resp.text}')
        except requests.ConnectionError:
            print(f'  ❌ Cannot connect to {API_BASE} — is the server running?')
        except requests.Timeout:
            print(f'  ⏳ Request timed out')

        time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(
        description='Simulate vehicle movement for Sarthi'
    )
    parser.add_argument(
        'vehicle_id',
        type=int,
        help='ID of the vehicle to simulate (get it from /api/vehicles/)',
    )
    parser.add_argument(
        '--interval',
        type=float,
        default=4.0,
        help='Seconds between location updates (default: 4)',
    )
    args = parser.parse_args()
    try:
        simulate(args.vehicle_id, args.interval)
    except KeyboardInterrupt:
        print('\n\n🛑 Simulator stopped.')
        sys.exit(0)


if __name__ == '__main__':
    main()
