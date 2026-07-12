from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from nakul_server import auth
from nakul_server.main import app


client = TestClient(app)


def test_authenticated_deployment_reports_missing_config(monkeypatch):
    monkeypatch.setenv("NAKUL_REQUIRE_AUTH", "true")
    for name in (
        "SUPABASE_URL",
        "SUPABASE_PUBLISHABLE_KEY",
        "SUPABASE_ANON_KEY",
        "SUPABASE_SECRET_KEY",
        "SUPABASE_SERVICE_ROLE_KEY",
    ):
        monkeypatch.delenv(name, raising=False)

    assert auth.missing_production_config() == [
        "SUPABASE_URL",
        "SUPABASE_PUBLISHABLE_KEY",
        "SUPABASE_SECRET_KEY",
    ]


def test_local_development_does_not_require_supabase_config(monkeypatch):
    monkeypatch.setenv("NAKUL_REQUIRE_AUTH", "false")

    assert auth.missing_production_config() == []


def test_authenticated_app_fails_fast_when_config_is_missing(monkeypatch):
    monkeypatch.setenv("NAKUL_REQUIRE_AUTH", "true")
    for name in (
        "SUPABASE_URL",
        "SUPABASE_PUBLISHABLE_KEY",
        "SUPABASE_ANON_KEY",
        "SUPABASE_SECRET_KEY",
        "SUPABASE_SERVICE_ROLE_KEY",
    ):
        monkeypatch.delenv(name, raising=False)

    with pytest.raises(RuntimeError, match="SUPABASE_URL"):
        with TestClient(app):
            pass


def test_paid_routes_require_a_session_in_production(monkeypatch):
    monkeypatch.setenv("NAKUL_REQUIRE_AUTH", "true")

    response = client.post(
        "/v1/query",
        json={"query": "aaj ka panchang", "lang": "en"},
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_malformed_authorization_header_is_rejected(monkeypatch):
    monkeypatch.setenv("NAKUL_REQUIRE_AUTH", "true")

    response = client.post(
        "/v1/query",
        headers={"authorization": "Basic abc"},
        json={"query": "aaj ka panchang", "lang": "en"},
    )

    assert response.status_code == 401


def test_valid_session_can_query(monkeypatch):
    monkeypatch.setenv("NAKUL_REQUIRE_AUTH", "true")
    verify = AsyncMock(return_value=auth.AuthenticatedUser(id="user-123"))
    monkeypatch.setattr(auth, "_verify", verify)

    response = client.post(
        "/v1/query",
        headers={"authorization": "Bearer user-token"},
        json={"query": "aaj ka panchang", "lang": "en"},
    )

    assert response.status_code == 200
    verify.assert_awaited_once_with("user-token")


def test_account_deletion_uses_authenticated_user(monkeypatch):
    monkeypatch.setenv("NAKUL_REQUIRE_AUTH", "true")
    user = auth.AuthenticatedUser(id="user-to-delete")
    monkeypatch.setattr(auth, "_verify", AsyncMock(return_value=user))
    delete = AsyncMock()
    monkeypatch.setattr(auth, "delete_user", delete)

    response = client.delete(
        "/v1/account",
        headers={"authorization": "Bearer user-token"},
    )

    assert response.status_code == 204
    delete.assert_awaited_once_with(user)


def test_guest_quota_blocks_the_sixth_query(monkeypatch):
    monkeypatch.setenv("NAKUL_REQUIRE_AUTH", "true")
    guest = auth.AuthenticatedUser(id="guest-user", is_anonymous=True)
    monkeypatch.setattr(auth, "_verify", AsyncMock(return_value=guest))
    quota = AsyncMock(side_effect=HTTPException(403, "guest_limit_reached"))
    monkeypatch.setattr(auth, "enforce_query_quota", quota)

    response = client.post(
        "/v1/query",
        headers={"authorization": "Bearer guest-token"},
        json={"query": "one more question", "lang": "en"},
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "guest_limit_reached"
    quota.assert_awaited_once_with(guest)
