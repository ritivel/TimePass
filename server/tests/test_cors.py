from fastapi.testclient import TestClient

from nakul_server.main import app


client = TestClient(app)


def _preflight(origin: str):
    return client.options(
        "/v1/query",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
        },
    )


def test_local_flutter_web_origin_is_allowed():
    response = _preflight("http://localhost:53721")
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:53721"


def test_arbitrary_web_origin_is_not_allowed():
    response = _preflight("https://untrusted.example")
    assert "access-control-allow-origin" not in response.headers


def test_operational_headers_include_safe_request_id():
    response = client.get(
        "/healthz",
        headers={"x-request-id": "client-request_123"},
    )

    assert response.status_code == 200
    assert response.headers["x-request-id"] == "client-request_123"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["referrer-policy"] == "no-referrer"


def test_invalid_request_id_is_replaced():
    response = client.get("/healthz", headers={"x-request-id": "bad id"})

    assert response.status_code == 200
    assert len(response.headers["x-request-id"]) == 32
