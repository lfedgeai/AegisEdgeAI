#!/usr/bin/env python3

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Mobile Location Verification Microservice

Implements the CAMARA Device Location verification flow so that the Keylime
Verifier can validate mobile sensor IDs via a REST API.
"""

import argparse
import logging
import os
import sqlite3
import sys
import threading
import time
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import requests
from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

LOG = logging.getLogger("mobile_sensor_service")

DEFAULT_SCOPE = os.getenv("MOBILE_SENSOR_SCOPE", "dpv:FraudPreventionAndDetection#device-location-read")
DEFAULT_SENSOR_ID = os.getenv("MOBILE_SENSOR_ID", "12d1:1433")
DEFAULT_SENSOR_IMEI = os.getenv("MOBILE_SENSOR_IMEI_DEFAULT", "356345043865103")
DEFAULT_SENSOR_IMSI = os.getenv("MOBILE_SENSOR_IMSI_DEFAULT", "214070610960475")
DEFAULT_MSISDN = os.getenv("MOBILE_SENSOR_MSISDN", "+34696810912")
DEFAULT_LATITUDE = float(os.getenv("MOBILE_SENSOR_LAT_DEFAULT", "40.33"))
DEFAULT_LONGITUDE = float(os.getenv("MOBILE_SENSOR_LON_DEFAULT", "-3.7707"))
DEFAULT_ACCURACY = float(os.getenv("MOBILE_SENSOR_ACC_DEFAULT", "7.0"))

# Prometheus metrics (Task 18: Observability)
REQUEST_COUNT = Counter(
    'sidecar_request_total',
    'Total verification requests',
    ['result']  # 'success' or 'failure'
)
CAMARA_LATENCY = Histogram(
    'sidecar_camara_api_latency_seconds',
    'CAMARA API call latency in seconds',
    buckets=[0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)
VERIFICATION_SUCCESS = Counter(
    'sidecar_location_verification_success_total',
    'Successful location verifications'
)
VERIFICATION_FAILURE = Counter(
    'sidecar_location_verification_failure_total',
    'Failed location verifications'
)

CAMARA_BASE = os.getenv(
    "CAMARA_BASE_URL", "https://sandbox.opengateway.telefonica.com/apigateway"
)
AUTHORIZE_PATH = os.getenv("CAMARA_AUTHORIZE_PATH", "/bc-authorize")
TOKEN_PATH = os.getenv("CAMARA_TOKEN_PATH", "/token")
VERIFY_PATH = os.getenv("CAMARA_VERIFY_PATH", "/location/v0/verify")


def _get_default_latitude() -> float:
    try:
        return float(os.getenv("MOBILE_SENSOR_LATITUDE", str(DEFAULT_LATITUDE)))
    except (ValueError, TypeError):
        return DEFAULT_LATITUDE


def _get_default_longitude() -> float:
    try:
        return float(os.getenv("MOBILE_SENSOR_LONGITUDE", str(DEFAULT_LONGITUDE)))
    except (ValueError, TypeError):
        return DEFAULT_LONGITUDE


def _get_default_accuracy() -> float:
    try:
        return float(os.getenv("MOBILE_SENSOR_ACCURACY", str(DEFAULT_ACCURACY)))
    except (ValueError, TypeError):
        return DEFAULT_ACCURACY


def _get_default_sensor_imei() -> Optional[str]:
    imei = os.getenv("MOBILE_SENSOR_IMEI", DEFAULT_SENSOR_IMEI)
    return imei if imei else None


def _get_default_sensor_imsi() -> Optional[str]:
    imsi = os.getenv("MOBILE_SENSOR_IMSI", DEFAULT_SENSOR_IMSI)
    return imsi if imsi else None


def _camara_bypass_enabled() -> bool:
    return os.getenv("CAMARA_BYPASS", "").lower() in ("1", "true", "yes", "on")


def _demo_mode_enabled() -> bool:
    demo_mode = os.getenv("DEMO_MODE", "").strip()
    if demo_mode:
        return demo_mode.lower() in ("1", "true", "yes", "on")
    else:
        return _camara_bypass_enabled()


def _get_verify_location_cache_ttl() -> int:
    try:
        ttl = int(os.getenv("CAMARA_VERIFY_CACHE_TTL_SECONDS", "900"))
        return 900 if ttl < 0 else ttl
    except (ValueError, TypeError):
        return 900


def _get_auth_req_id_file_path() -> Path:
    db_path = Path(os.getenv("MOBILE_SENSOR_DB", "sensor_mapping.db"))
    db_dir = db_path.parent if db_path.is_absolute() else Path.cwd()
    return db_dir / "camara_auth_req_id.txt"


class SensorDatabase:
    """Simple SQLite-backed storage for sensor metadata."""

    def __init__(self, db_path: Path, recreate_db: bool = False):
        self.db_path = db_path
        if recreate_db and self.db_path.exists():
            LOG.info("Deleting existing database: %s", self.db_path)
            self.db_path.unlink()
        self._ensure_schema()

    def _ensure_schema(self) -> None:
        conn = sqlite3.connect(self.db_path)
        try:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS sensor_map (
                    sensor_id TEXT,
                    sensor_imei TEXT,
                    sensor_imsi TEXT,
                    sensor_serial TEXT,
                    sensor_type TEXT DEFAULT 'mobile',
                    msisdn TEXT,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    accuracy REAL NOT NULL,
                    PRIMARY KEY (sensor_id, sensor_imei, sensor_imsi, sensor_serial)
                )
                """
            )
            # Create indexes
            conn.execute("CREATE INDEX IF NOT EXISTS idx_sensor_id ON sensor_map(sensor_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_sensor_imei ON sensor_map(sensor_imei)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_sensor_imsi ON sensor_map(sensor_imsi)")

            # Seed default data
            conn.execute(
                "INSERT OR REPLACE INTO sensor_map VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (DEFAULT_SENSOR_ID, _get_default_sensor_imei(), _get_default_sensor_imsi(), None, 'mobile', DEFAULT_MSISDN, _get_default_latitude(), _get_default_longitude(), _get_default_accuracy())
            )
            conn.commit()
        finally:
            conn.close()

    def get_sensor(self, sensor_id=None, imei=None, imsi=None, serial=None) -> Optional[Dict[str, Any]]:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            row = None
            if serial:
                row = conn.execute("SELECT * FROM sensor_map WHERE sensor_serial = ?", (serial,)).fetchone()
            elif imei and imsi:
                row = conn.execute("SELECT * FROM sensor_map WHERE sensor_imei = ? AND sensor_imsi = ?", (imei, imsi)).fetchone()
            elif sensor_id:
                row = conn.execute("SELECT * FROM sensor_map WHERE sensor_id = ?", (sensor_id,)).fetchone()
            return dict(row) if row else None
        finally:
            conn.close()


class CamaraClient:
    """Encapsulates CAMARA API calls with caching and token management."""

    def __init__(self, basic_auth: str, scope: str = DEFAULT_SCOPE, auth_req_id: Optional[str] = None):
        self.basic_auth = basic_auth
        self.scope = scope
        self._access_token: Optional[str] = None
        self._token_expires_at: Optional[float] = None
        self._token_lock = threading.Lock()

        self._verify_cache_ttl = _get_verify_location_cache_ttl()
        self._verify_cache_result: Optional[bool] = None
        self._verify_cache_timestamp: Optional[float] = None
        self._verify_cache_lock = threading.Lock()

        self.auth_req_id = auth_req_id or self._load_auth_req_id_from_file()
        if self.auth_req_id:
            self._save_auth_req_id_to_file(self.auth_req_id)

    def _load_auth_req_id_from_file(self) -> Optional[str]:
        try:
            path = _get_auth_req_id_file_path()
            return path.read_text(encoding="utf-8").strip() if path.exists() else None
        except Exception:
            return None

    def _save_auth_req_id_to_file(self, auth_req_id: str):
        try:
            path = _get_auth_req_id_file_path()
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(auth_req_id, encoding="utf-8")
        except Exception:
            pass

    def _headers(self, content_type: str) -> dict:
        return {"accept": "application/json", "authorization": self.basic_auth, "content-type": content_type}

    def _bearer_headers(self, token: str) -> dict:
        return {"accept": "application/json", "authorization": f"Bearer {token}", "content-type": "application/json"}

    def authorize(self, msisdn: str) -> str:
        if self.auth_req_id:
            return self.auth_req_id

        payload = {"login_hint": f"tel:{msisdn}", "scope": self.scope}
        resp = requests.post(f"{CAMARA_BASE}{AUTHORIZE_PATH}", headers=self._headers("application/x-www-form-urlencoded"), data=payload, timeout=30)
        resp.raise_for_status()
        self.auth_req_id = resp.json().get("auth_req_id")
        if self.auth_req_id:
            self._save_auth_req_id_to_file(self.auth_req_id)
        return self.auth_req_id

    def get_access_token(self) -> str:
        with self._token_lock:
            if self._access_token and self._token_expires_at and time.time() < (self._token_expires_at - 60):
                return self._access_token

            if not self.auth_req_id:
                raise RuntimeError("auth_req_id missing")

            resp = requests.post(f"{CAMARA_BASE}{TOKEN_PATH}", headers=self._headers("application/x-www-form-urlencoded"), data={"grant_type": "urn:openid:params:grant-type:ciba", "auth_req_id": self.auth_req_id}, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            self._access_token = data.get("access_token")
            self._token_expires_at = time.time() + int(data.get("expires_in", 3600))
            return self._access_token

    def verify_location(self, msisdn: str, lat: float, lon: float, acc: float, token: str, skip_cache: bool = False) -> bool:
        if not skip_cache and self._verify_cache_ttl > 0:
            with self._verify_cache_lock:
                if self._verify_cache_result is not None and self._verify_cache_timestamp and (time.time() - self._verify_cache_timestamp) < self._verify_cache_ttl:
                    LOG.info("[CACHE HIT] Using cached verification result")
                    return self._verify_cache_result

        payload = {"ueId": {"msisdn": msisdn}, "latitude": lat, "longitude": lon, "accuracy": acc}
        LOG.info("[API CALL] CAMARA verify_location API call: %s", payload)
        with CAMARA_LATENCY.time():
            resp = requests.post(f"{CAMARA_BASE}{VERIFY_PATH}", headers=self._bearer_headers(token), json=payload, timeout=30)
        resp.raise_for_status()
        result = bool(resp.json().get("verificationResult"))

        if self._verify_cache_ttl > 0:
            with self._verify_cache_lock:
                self._verify_cache_result = result
                self._verify_cache_timestamp = time.time()

        return result


class LocationVerifier(ABC):
    @abstractmethod
    def verify(self, sensor_data: Dict[str, Any], skip_cache: bool = False) -> bool:
        pass


class CamaraVerifier(LocationVerifier):
    def __init__(self, client: Optional[CamaraClient], bypass: bool):
        self.client = client
        self.bypass = bypass

    def verify(self, sensor_data: Dict[str, Any], skip_cache: bool = False) -> bool:
        imei = sensor_data.get("sensor_imei")
        imsi = sensor_data.get("sensor_imsi")
        if imei or imsi:
            LOG.info("[FUTURE-PROOF] Hardware identifiers present: imei=%s, imsi=%s", imei, imsi)

        if self.bypass:
            if not _demo_mode_enabled():
                LOG.info("CAMARA_BYPASS enabled: automatically approving")
            return True

        if not self.client:
            LOG.error("CamaraVerifier not initialized")
            return False

        msisdn = sensor_data.get("msisdn")
        lat, lon = sensor_data.get("latitude"), sensor_data.get("longitude")
        acc = sensor_data.get("accuracy", 1000.0)

        if not msisdn or lat is None or lon is None:
            LOG.error("Missing verification data: msisdn=%s, loc=(%s, %s)", msisdn, lat, lon)
            return False

        camara_msisdn = msisdn[4:] if msisdn.startswith("tel:") else (msisdn[1:] if msisdn.startswith("+") else msisdn)

        try:
            token = self.client.get_access_token()
            return self.client.verify_location(camara_msisdn, lat, lon, acc, token, skip_cache=skip_cache)
        except Exception as e:
            LOG.error("Verification flow failed: %s", e)
            return False


def create_app(db_path: Path) -> Flask:
    app = Flask(__name__)
    database = SensorDatabase(db_path)
    bypass = _camara_bypass_enabled()

    camara_client = None
    auth = os.getenv("CAMARA_BASIC_AUTH")
    auth_file = os.getenv("CAMARA_BASIC_AUTH_FILE")
    if auth_file and os.path.exists(auth_file):
        auth = Path(auth_file).read_text().strip()

    if auth and not bypass:
        try:
            camara_client = CamaraClient(auth)
            camara_client.authorize(DEFAULT_MSISDN)
        except Exception as e:
            LOG.warning("CamaraClient init failed: %s. Falling back to bypass.", e)
            bypass = True

    verifiers = {"mobile": CamaraVerifier(camara_client, bypass)}

    @app.route("/verify", methods=["POST"])
    def verify():
        # Increment request total (Task 18: Observability)
        REQUEST_COUNT.labels(result='total').inc()
        
        payload = request.get_json(force=True) or {}
        LOG.info("Request: %s", payload)

        # Healthcheck or empty request
        if not payload or "sensor_id" not in payload:
            payload = {"sensor_id": DEFAULT_SENSOR_ID, "sensor_type": "mobile"}

        sensor_id = payload.get("sensor_id")
        sensor_type = payload.get("sensor_type", "mobile")

        # SVID-based flow (DB-less)
        msisdn = payload.get("msisdn")
        lat, lon = payload.get("latitude"), payload.get("longitude")

        if msisdn and lat is not None and lon is not None:
            LOG.info("DB-LESS flow: using data from SVID claims")
            sensor = {
                "sensor_id": sensor_id,
                "sensor_type": sensor_type,
                "msisdn": msisdn,
                "latitude": lat,
                "longitude": lon,
                "accuracy": payload.get("accuracy", 1000.0),
                "sensor_imei": payload.get("sensor_imei"),
                "sensor_imsi": payload.get("sensor_imsi"),
            }
        else:
            LOG.info("DB-BASED flow: looking up sensor %s", sensor_id)
            sensor = database.get_sensor(sensor_id, payload.get("sensor_imei"), payload.get("sensor_imsi"), payload.get("sensor_serial_number"))
            if not sensor:
                LOG.error("Sensor not found in DB: %s", sensor_id)
                REQUEST_COUNT.labels(result='error').inc()
                return jsonify({"error": "sensor_not_found"}), 404

        verifier = verifiers.get(sensor.get("sensor_type"))
        if not verifier:
            REQUEST_COUNT.labels(result='error').inc()
            return jsonify({"error": f"unsupported_sensor_type_in_mobile_sidecar: {sensor.get('sensor_type')}"}), 400

        result = verifier.verify(sensor, skip_cache=payload.get("skip_cache", False))
        
        # Record metrics
        if result:
            REQUEST_COUNT.labels(result='success').inc()
            VERIFICATION_SUCCESS.inc()
        else:
            REQUEST_COUNT.labels(result='failure').inc()
            VERIFICATION_FAILURE.inc()
        
        return jsonify({"verification_result": result, **sensor})

    @app.route("/lookup_msisdn", methods=["POST"])
    def lookup():
        payload = request.get_json(force=True) or {}
        sensor = database.get_sensor(payload.get("sensor_id"), payload.get("sensor_imei"), payload.get("sensor_imsi"), payload.get("sensor_serial_number"))
        if not sensor or not sensor.get("msisdn"):
            return jsonify({"found": False})
        msisdn = sensor["msisdn"]
        return jsonify({
            "found": True,
            "sensor_msisdn": msisdn if msisdn.startswith("tel:") else f"tel:{msisdn}",
            "sensor_id": sensor["sensor_id"],
            "latitude": sensor.get("latitude", 0.0),
            "longitude": sensor.get("longitude", 0.0),
            "accuracy": sensor.get("accuracy", 0.0),
        })

    @app.route("/metrics", methods=["GET"])
    def metrics():
        """Prometheus metrics endpoint."""
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    return app

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9050)
    args = parser.parse_args()

    db_path = Path(os.getenv("MOBILE_SENSOR_DB", "sensor_mapping.db"))
    app = create_app(db_path)
    LOG.info("Mobile Sensor Sidecar (Pure Mobile) listening on %s:%s", args.host, args.port)
    app.run(host=args.host, port=args.port)
