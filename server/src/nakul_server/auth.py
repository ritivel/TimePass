"""Supabase access-token verification and privileged account operations.

The Flutter app sends the user's short-lived access token. The orchestrator
validates it against Supabase Auth before serving paid API routes. No service
credential is ever returned to the client.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Annotated

import httpx
from fastapi import Header, HTTPException, status


@dataclass(frozen=True)
class AuthenticatedUser:
    id: str
    email: str | None = None
    is_anonymous: bool = False


def _supabase_config() -> tuple[str, str]:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    publishable_key = os.environ.get("SUPABASE_PUBLISHABLE_KEY") or os.environ.get(
        "SUPABASE_ANON_KEY", ""
    )
    return url, publishable_key


def auth_required() -> bool:
    return os.environ.get("NAKUL_REQUIRE_AUTH", "false").lower() in {
        "1",
        "true",
        "yes",
    }


def missing_production_config() -> list[str]:
    """Return fail-fast configuration gaps for an authenticated deployment."""
    if not auth_required():
        return []
    url, publishable_key = _supabase_config()
    secret_key = os.environ.get("SUPABASE_SECRET_KEY") or os.environ.get(
        "SUPABASE_SERVICE_ROLE_KEY", ""
    )
    missing = []
    if not url:
        missing.append("SUPABASE_URL")
    if not publishable_key:
        missing.append("SUPABASE_PUBLISHABLE_KEY")
    if not secret_key:
        missing.append("SUPABASE_SECRET_KEY")
    return missing


async def _verify(token: str) -> AuthenticatedUser:
    url, publishable_key = _supabase_config()
    if not url or not publishable_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="authentication is not configured",
        )
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(
                f"{url}/auth/v1/user",
                headers={
                    "apikey": publishable_key,
                    "authorization": f"Bearer {token}",
                },
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="authentication service unavailable",
        ) from exc
    if response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid or expired session",
            headers={"WWW-Authenticate": "Bearer"},
        )
    payload = response.json()
    user_id = payload.get("id")
    if not isinstance(user_id, str) or not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid session user",
        )
    email = payload.get("email")
    return AuthenticatedUser(
        id=user_id,
        email=email if isinstance(email, str) else None,
        is_anonymous=payload.get("is_anonymous") is True,
    )


async def require_user(
    authorization: Annotated[str | None, Header()] = None,
) -> AuthenticatedUser:
    if not authorization:
        if not auth_required():
            return AuthenticatedUser(id="local-development")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="sign in required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return await _verify(token)


async def delete_user(user: AuthenticatedUser) -> None:
    url, _ = _supabase_config()
    secret_key = os.environ.get("SUPABASE_SECRET_KEY") or os.environ.get(
        "SUPABASE_SERVICE_ROLE_KEY", ""
    )
    if not url or not secret_key or user.id == "local-development":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="account deletion is not configured",
        )
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.delete(
                f"{url}/auth/v1/admin/users/{user.id}",
                headers=_secret_headers(secret_key),
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="account service unavailable",
        ) from exc
    if response.status_code not in {200, 204}:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="account deletion failed",
        )


def _secret_headers(secret_key: str) -> dict[str, str]:
    headers = {"apikey": secret_key}
    # Legacy service_role keys are JWTs and require Bearer auth. Current
    # sb_secret_* keys are opaque and belong in the apikey header only.
    if not secret_key.startswith("sb_secret_"):
        headers["authorization"] = f"Bearer {secret_key}"
    return headers


async def enforce_query_quota(user: AuthenticatedUser) -> None:
    """Atomically consume one of an anonymous user's five trial queries."""
    if not user.is_anonymous:
        return
    url, _ = _supabase_config()
    secret_key = os.environ.get("SUPABASE_SECRET_KEY") or os.environ.get(
        "SUPABASE_SERVICE_ROLE_KEY", ""
    )
    if not url or not secret_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="guest quota is not configured",
        )
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                f"{url}/rest/v1/rpc/consume_guest_query",
                headers={**_secret_headers(secret_key), "content-type": "application/json"},
                json={"target_user_id": user.id},
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="guest quota service unavailable",
        ) from exc
    if response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="guest quota check failed",
        )
    count = response.json()
    if not isinstance(count, int):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="guest quota response invalid",
        )
    if count > 5:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="guest_limit_reached",
        )
