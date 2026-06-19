#!/usr/bin/env python3
"""
Integration Test Suite — DR Drill Validation
Run against DR site after failover to confirm full functionality.
Author: Venkatesh Nagelli

Usage: pytest test_dr_drill.py --base-url https://dr-site.example.com
"""

import pytest
import requests


def pytest_addoption(parser):
    parser.addoption("--base-url", action="store", default="https://localhost")


@pytest.fixture
def base_url(request):
    return request.config.getoption("--base-url")


class TestDRSiteHealth:

    def test_health_endpoint_responds(self, base_url):
        resp = requests.get(f"{base_url}/health", timeout=10)
        assert resp.status_code == 200
        assert resp.json().get("status") == "UP"

    def test_database_connectivity(self, base_url):
        resp = requests.get(f"{base_url}/health/db", timeout=10)
        assert resp.status_code == 200
        assert resp.json().get("database") == "connected"

    def test_write_operation_succeeds(self, base_url):
        """Critical: confirm DR site can actually accept writes, not just reads."""
        resp = requests.post(
            f"{base_url}/health/write-test",
            json={"test_id": "dr-drill-write-check"},
            timeout=10
        )
        assert resp.status_code in (200, 201)

    def test_read_after_write_consistency(self, base_url):
        """Confirm a write is immediately readable (no replication lag on DR primary)."""
        write_resp = requests.post(
            f"{base_url}/health/write-test",
            json={"test_id": "dr-drill-raw-check"},
            timeout=10
        )
        assert write_resp.status_code in (200, 201)

        read_resp = requests.get(
            f"{base_url}/health/write-test/dr-drill-raw-check",
            timeout=10
        )
        assert read_resp.status_code == 200

    def test_replication_lag_within_bounds(self, base_url):
        resp = requests.get(f"{base_url}/health/replication-lag", timeout=10)
        assert resp.status_code == 200
        lag_seconds = resp.json().get("lag_seconds", 9999)
        assert lag_seconds < 60, f"Replication lag too high: {lag_seconds}s"

    def test_response_time_acceptable(self, base_url):
        resp = requests.get(f"{base_url}/api/v1/status", timeout=10)
        assert resp.elapsed.total_seconds() < 2.0, "DR site responding too slowly"

    @pytest.mark.parametrize("endpoint", [
        "/api/v1/accounts",
        "/api/v1/transactions",
        "/api/v1/users/me",
    ])
    def test_critical_api_endpoints_reachable(self, base_url, endpoint):
        resp = requests.get(f"{base_url}{endpoint}", timeout=10)
        # 401 is acceptable (auth required) — we're testing reachability, not auth
        assert resp.status_code in (200, 401), f"{endpoint} unreachable: {resp.status_code}"
