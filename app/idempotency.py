"""Idempotency-Key для POST /books: повтор запиту з тим самим ключем повертає
збережену відповідь і не створює другий запис у БД."""
import hashlib
import json
from collections.abc import Callable

from fastapi import HTTPException, Response, status

from . import cache
from .config import get_settings

PROCESSING_TTL_SECONDS = 60


def run_once(user_sub: str, key: str, payload_json: str, execute: Callable[[], tuple[int, str]]) -> Response:
    r = cache.client()
    if r is None:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Idempotency storage is not configured")

    redis_key = f"idem:{user_sub}:{key}"
    fingerprint = hashlib.sha256(payload_json.encode()).hexdigest()

    # SET NX — атомарно «захоплюємо» ключ; паралельний дубль отримає False
    claimed = r.set(
        redis_key,
        json.dumps({"state": "processing", "fp": fingerprint}),
        nx=True,
        ex=PROCESSING_TTL_SECONDS,
    )
    if not claimed:
        raw = r.get(redis_key)
        if raw is None:
            raise HTTPException(status.HTTP_409_CONFLICT, "Request with this key is in progress, retry later")
        saved = json.loads(raw)
        if saved["fp"] != fingerprint:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY, "Idempotency-Key was already used with a different body"
            )
        if saved["state"] == "processing":
            raise HTTPException(status.HTTP_409_CONFLICT, "Request with this key is in progress, retry later")
        return Response(
            content=saved["body"],
            status_code=saved["status"],
            media_type="application/json",
            headers={"Idempotent-Replayed": "true"},
        )

    try:
        status_code, body = execute()
    except Exception:
        r.delete(redis_key)  # операція не виконалась — клієнт може повторити з тим самим ключем
        raise

    r.set(
        redis_key,
        json.dumps({"state": "done", "fp": fingerprint, "status": status_code, "body": body}),
        ex=get_settings().idempotency_ttl_seconds,
    )
    return Response(content=body, status_code=status_code, media_type="application/json")
