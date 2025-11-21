import sqlite3
from pathlib import Path
from unittest import mock

import pytest
import requests

from service import create_app, DEFAULT_SENSOR_ID, DEFAULT_MSISDN


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
        "CREATE TABLE sensor_map (sensor_id TEXT PRIMARY KEY, msisdn TEXT NOT NULL)"
    )
    conn.execute(
        "INSERT INTO sensor_map(sensor_id, msisdn) VALUES (?, ?)",
        (DEFAULT_SENSOR_ID, DEFAULT_MSISDN),
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
            json={
                "sensor_id": DEFAULT_SENSOR_ID,
                "latitude": 40.33,
                "longitude": -3.7707,
                "accuracy": 7,
            },
        )

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == DEFAULT_SENSOR_ID
    assert data["verification_result"] is True


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
            json={
                "latitude": 40.33,
                "longitude": -3.7707,
                "accuracy": 7,
            },
        )

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == DEFAULT_SENSOR_ID
    assert data["verification_result"] is True


def test_unknown_sensor_returns_404(config_env):
    app = create_app(Path(config_env))
    client = app.test_client()

    resp = client.post(
        "/verify",
        json={
            "sensor_id": "missing",
            "latitude": 1.0,
            "longitude": 2.0,
            "accuracy": 5,
        },
    )
    assert resp.status_code == 404
import sqlite3
from pathlib import Path
from unittest import mock

import pytest
import requests

from service import create_app, DEFAULT_SENSOR_ID, DEFAULT_MSISDN


class DummyResponse:
    def __init__(self, payload, status_code=200):
        this = payload
*** End Patch
import sqlite3
from pathlib import Path
from unittest import mock

import pytest
import requests

from service import create_app, DEFAULT_SENSOR_ID, DEFAULT_MSISDN


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
        "CREATE TABLE sensor_map (sensor_id TEXT PRIMARY KEY, msisdn TEXT NOT NULL)"
    )
    conn.execute(
        "INSERT INTO sensor_map(sensor_id, msisdn) VALUES (?, ?)",
        (DEFAULT_SENSOR_ID, DEFAULT_MSISDN),
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
            json={
                "sensor_id": DEFAULT_SENSOR_ID,
                "latitude": 40.33,
                "longitude": -3.7707,
                "accuracy": 7,
            },
        )

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == DEFAULT_SENSOR_ID
    assert data["verification_result"] is True


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
            json={
                "latitude": 40.33,
                "longitude": -3.7707,
                "accuracy": 7,
            },
        )

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == DEFAULT_SENSOR_ID
    assert data["verification_result"] is True


def test_unknown_sensor_returns_404(config_env):
    app = create_app(Path(config_env))
    client = app.test_client()

    resp = client.post(
        "/verify",
        json={
            "sensor_id": "missing",
            "latitude": 1.0,
            "longitude": 2.0,
            "accuracy": 5,
        },
    )
    assert resp.status_code == 404
import sqlite3
from pathlib import Path
from unittest import mock

import pytest
import requests

from service import create_app


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
        "CREATE TABLE sensor_map (sensor_id TEXT PRIMARY KEY, msisdn TEXT NOT NULL)"
    )
    conn.execute(
        "INSERT INTO sensor_map(sensor_id, msisdn) VALUES (?, ?)",
        ("12d1:1433", "+34696810912"),
    )
    conn.commit()
    conn.close()
    monkeypatch.setenv("MOBILE_SENSOR_DB", str(db_path))
    monkeypatch.setenv("CAMARA_BASIC_AUTH", "Basic test-token")
    return db_path


def test_verify_success(config_env, monkeypatch):
    app = create_app(Path(config_env))
    client = app.test_client()

    def fake_post(url, headers=None, data=None, json=None, timeout=None):
        if url.endswith("bc-authorize"):
            return DummyResponse({"auth_req_id": "req-123"})
        if url.endswith("token"):
            return DummyResponse({"access_token": "token-xyz"})
        if url.endswith("location/v0/verify"):
            assert json["ueId"]["msisdn"] == "+34696810912"
            return DummyResponse({"verificationResult": True})
        raise AssertionError(f"Unexpected URL {url}")

    with mock.patch("service.requests.post", side_effect=fake_post):
        resp = client.post(
            "/verify",
            json={
                "sensor_id": "12d1:1433",
                "latitude": 40.33,
                "longitude": -3.7707,
                "accuracy": 7,
            },
        )

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == "12d1:1433"
    assert data["verification_result"] is True


def test_unknown_sensor_returns_404(config_env):
    app = create_app(Path(config_env))
    client = app.test_client()
    resp = client.post(
        "/verify",
        json={
            "sensor_id": "missing",
            "latitude": 1.0,
            "longitude": 2.0,
            "accuracy": 5,
        },
    )
    assert resp.status_code == 404
import json
import os
import sqlite3
import tempfile
from pathlib import Path
from unittest import mock

import pytest

from service import create_app


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
def temp_db(tmp_path, monkeypatch):
    db_path = tmp_path / "sensors.db"
    conn = sqlite3.connect(db_path)
    conn.execute(
        "CREATE TABLE sensor_map (sensor_id TEXT PRIMARY KEY, msisdn TEXT NOT NULL)"
    )
    conn.execute(
        "INSERT INTO sensor_map(sensor_id, msisdn) VALUES (?, ?)",
        ("12d1:1433", "+34696810912"),
    )
    conn.commit()
    conn.close()
    monkeypatch.setenv("MOBILE_SENSOR_DB", str(db_path))
    monkeyatch = monkeypatch
    monkeypatch.setenv("CAMARA_BASIC_AUTH", "Basic test-token")
    yield db_path


def test_verify_success(temp_db, monkeypatch):
    app = create_app(Path(temp_db))
    client = app.test_client()

    call_order = []

    def fake_post(url, headers=None, data=None, json=None, timeout=None):
        call_order.append(url)
        if url.endswith("bc-authorize"):
            return DummyResponse({"auth_req_id": "req-123"})
        if url.endswith("token"):
            return DummyResponse({"access_token": "token-abc"})
        if url.endswith("location/v0/verify"):
            assert json["ueId"]["msisdn"] == "+34696810912"
            return DummyResponse({"verificationResult": True})
        raise AssertionError(f"Unexpected URL {url}")

    monkeypatch = mock.patch("service.requests.post", side_effect=fake_post)
    with monkeypatch:
        response = client.post(
            "/verify",
            json={
                "sensor_id": "12d1:1433",
                "latitude": 40.33,
                "longitude": -3.7707,
                "accuracy": 7,
            },
        )

    assert response.status_code == 200
    data = response.get_json()
    assert data["sensor_id"] == "12d1:1433"
    assert data["verification_result"] is True
    assert call_order == [
        "https://sandbox.opengateway.telefonica.com/apigateway/bc-authorize",
        "https://sandbox.opengateway.telefonica.com/apigateway/token",
        "https://sandbox.opengateway.telefonica.com/apigateway/location/v0/verify",
    ]


def test_unknown_sensor_returns_404(temp_db):
    app = create_app(Path(temp_db))
    client = app.test_client()

    response = client.post(
        "/verify",
        json={"sensor_id": "missing", "latitude": 1, "longitude": 2, "accuracy": 5},
    )

    assert response.status_code == 404
import json
import os
import sqlite3
import tempfile
from pathlib import Path
from unittest import mock

import pytest

from service import CamaraClient, SensorDatabase, create_app


class FakeResponse:
    def __init__(self, payload, status_code=200):
        self._payload = payload
        self.status_code = status_code

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(f"status {self.status_code}")


@pytest.fixture(autouse=True)
def configure_env(monkeypatch):
    monkeypatch.setenv("CAMARA_BASIC_AUTH", "Basic test-credential")
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    try:
        conn = sqlite3.connect(path)
        conn.execute(
            "CREATE TABLE sensor_map (sensor_id TEXT PRIMARY KEY, msisdn TEXT NOT NULL)"
        )
        conn.execute(
            "INSERT INTO sensor_map(sensor_id, msisdn) VALUES (?, ?)",
            ("12d1:1433", "+34696810912"),
        )
        conn.commit()
        conn.close()
        yield Path(path)
    finally:
        if os.path.exists(path):
            os.remove(path)


def test_verify_success(configure_env, monkeypatch):
    db_path = configure_env
    app = create_app(db_path)
    client = app.test_client()

    def fake_post(url, headers=None, data=None, json=None, timeout=None):
        if url.endswith("bc-authorize"):
            return FakeResponse({"auth_req_id": "req-123"})
        if url.endswith("token"):
            return FakeResponse({"access_token": "token-xyz"})
        if url.endswith("location/v0/verify"):
            return FakeResponse({"verificationResult": True})
        raise AssertionError(f"Unexpected URL {url}")

    monkeypatch.setattr("service.requests.post", fake_post)

    resp = client.post(
        "/verify",
        json={
            "sensor_id": "12d1:1433",
            "latitude": 40.33,
            "longitude": -3.7707,
            "accuracy": 7,
        },
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["sensor_id"] == "12d1:1433"
    assert data["verification_result"] is True


def test_unknown_sensor(configure_env):
    db_path = configure_env
    app = create_app(db_path)
    client = app.test_client()

    resp = client.post(
        "/verify",
        json={
            "sensor_id": "unknown",
            "latitude": 1.0,
            "longitude": 2.0,
            "accuracy": 5,
        },
    )
    assert resp.status_code == 404

