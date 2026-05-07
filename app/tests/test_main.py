from app.main import app


def test_hello():
    client = app.test_client()
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.json["message"] == "Hello, Candidate"


def test_healthz():
    client = app.test_client()
    resp = client.get("/healthz")
    assert resp.status_code == 200


def test_metrics():
    client = app.test_client()
    client.get("/")
    resp = client.get("/metrics")
    body = resp.get_data(as_text=True)
    assert resp.status_code == 200
    assert "text/plain" in resp.content_type
    assert "http_requests_total" in body
    assert 'method="GET"' in body
    assert 'path="/"' in body
    assert 'status="200"' in body
    assert "http_request_duration_seconds" in body
