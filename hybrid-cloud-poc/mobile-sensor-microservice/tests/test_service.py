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

import sqlite3
import sys
from pathlib import Path
from unittest import mock

import pytest
import requests

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT))

from service import create_app, DEFAULT_SENSOR_ID, DEFAULT_MSISDN  # noqa: E402


class DummyResponse:
    def __init__(self, payload, status_code=200):
        self.payload = payload
        self.status_code = status_code

    def json(self):
        return self.payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(f"status={self.status_code}")


@pytest.fixture()
def config_env(tmp_path, monkeypatch):
    db_path = tmp_path / "sensors.db"
    conn = sqlite3.connect(db_path)
    conn.execute(
        """
        CREATE TABLE sensor_map (
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
    conn.execute(
        """
        INSERT INTO sensor_map(sensor_id, sensor_imei, sensor_imsi, sensor_serial, sensor_type, msisdn, latitude, longitude, accuracy)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (DEFAULT_SENSOR_ID, "356345043865103", "214070610960475", None, 'mobile', DEFAULT_MSISDN, 40.33, -3.7707, 7.0),
    )
    conn.commit()
    conn.close()
    monkeypatch.setenv("MOBILE_SENSOR_DB", str(db_path))
    monkeypatch.setenv("CAMARA_BASIC_AUTH", "Basic test-token")
    return db_path


def test_verify_success(config_env):
    app = create_app(Path(config_env))
    client = app.test_client()

    def fake_post(url, headers=None, data=None, json=None, timeout=None):
        if url.endswith("bc-authorize"):
            return DummyResponse({"auth_req_id": "req-123"})
        if url.endswith("token"):
            return DummyResponse({"access_token": "token-xyz"})
        if url.endswith("location/v0/verify"):
            assert json["ueId"]["msisdn"] == DEFAULT_MSISDN
            return DummyResponse({"verificationResult": True})
        raise AssertionError(f"Unexpected URL {url}")

    with mock.patch("service.requests.post", side_effect=fake_post):
        resp = client.post(
            "/verify",
            json={"sensor_id": DEFAULT_SENSOR_ID},
        )

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == DEFAULT_SENSOR_ID
    assert data["verification_result"] is True
    assert data["latitude"] == 40.33
    assert data["longitude"] == -3.7707
    assert data["accuracy"] == 7.0


def test_missing_sensor_uses_default(config_env):
    app = create_app(Path(config_env))
    client = app.test_client()

    def fake_post(url, headers=None, data=None, json=None, timeout=None):
        if url.endswith("bc-authorize"):
            return DummyResponse({"auth_req_id": "req-123"})
        if url.endswith("token"):
            return DummyResponse({"access_token": "token-xyz"})
        if url.endswith("location/v0/verify"):
            assert json["ueId"]["msisdn"] == DEFAULT_MSISDN
            return DummyResponse({"verificationResult": True})
        raise AssertionError(f"Unexpected URL {url}")

    with mock.patch("service.requests.post", side_effect=fake_post):
        resp = client.post(
            "/verify",
            json={},
        )

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == DEFAULT_SENSOR_ID
    assert data["verification_result"] is True
    assert data["latitude"] == 40.33
    assert data["longitude"] == -3.7707
    assert data["accuracy"] == 7.0


def test_unknown_sensor_returns_404(config_env):
    app = create_app(Path(config_env))
    client = app.test_client()

    resp = client.post(
        "/verify",
        json={"sensor_id": "missing"},
    )
    assert resp.status_code == 404


def test_camara_bypass(config_env, monkeypatch):
    monkeypatch.setenv("CAMARA_BYPASS", "true")
    app = create_app(Path(config_env))
    client = app.test_client()

    resp = client.post(
        "/verify",
        json={"sensor_id": DEFAULT_SENSOR_ID},
    )

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == DEFAULT_SENSOR_ID
    assert data["verification_result"] is True
