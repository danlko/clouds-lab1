"""Два однакові POST /books з одним Idempotency-Key → один запис у БД, дві однакові відповіді.

Запуск (локально, compose):  python3 tests/test_idempotency.py
У хмарі:  BASE_URL=$(terraform -chdir=infra output -raw app_url) TOKEN=$(./scripts/get_token.sh) python3 tests/test_idempotency.py
Сумісний з pytest.
"""
import json
import os
import urllib.parse
import urllib.request
import uuid

BASE_URL = os.environ.get("BASE_URL", "http://localhost:8000").rstrip("/")
TOKEN = os.environ.get("TOKEN", "")


def request(method: str, path: str, body: dict | None = None, headers: dict | None = None):
    req = urllib.request.Request(BASE_URL + path, method=method, headers=headers or {})
    if body is not None:
        req.data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    if TOKEN:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.status, resp.headers, resp.read().decode()


def test_same_key_creates_one_record():
    key = str(uuid.uuid4())
    author = f"idem-test-{key[:8]}"
    payload = {"title": "Idempotent book", "author": author, "year": 2024}

    s1, h1, b1 = request("POST", "/books", payload, {"Idempotency-Key": key})
    s2, h2, b2 = request("POST", "/books", payload, {"Idempotency-Key": key})

    assert s1 == s2 == 201
    assert b1 == b2, "відповіді мають бути однаковими"
    assert h2.get("Idempotent-Replayed") == "true"

    _, _, author_body = request("GET", "/authors/" + urllib.parse.quote(author))
    assert json.loads(author_body)["books_count"] == 1, "у БД має бути рівно один запис"
    print(f"OK: key={key}\n  1st: {s1} {b1}\n  2nd: {s2} {b2} (Idempotent-Replayed: true)\n  books by {author}: 1")


if __name__ == "__main__":
    test_same_key_creates_one_record()
