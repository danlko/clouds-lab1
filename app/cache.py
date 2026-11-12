"""Спільний кеш у Redis (cache-aside) + сховище для Idempotency-Key.

Redis — окремий сервіс, спільний для всіх екземплярів застосунку, тому всі вони
бачать один і той самий кеш. Якщо Redis недоступний, сервіс працює далі напряму з БД.
"""
import logging
import time
from functools import lru_cache

import redis

from .config import get_settings

log = logging.getLogger("uvicorn.error")

FLAG_KEY = "config:cache_enabled"
STATS_KEY = "cache:stats"
LIST_PREFIX = "books:list:"

_flag_value: bool | None = None
_flag_checked_at = 0.0
FLAG_REFRESH_SECONDS = 5


@lru_cache
def client() -> redis.Redis | None:
    s = get_settings()
    if not s.redis_host:
        return None
    return redis.Redis(
        host=s.redis_host,
        port=s.redis_port,
        socket_timeout=0.3,
        socket_connect_timeout=0.3,
        health_check_interval=30,
    )


def enabled() -> bool:
    """Чи ввімкнено кеш. Прапорець живе в Redis (перемикається через PUT /admin/cache
    без передеплою); кожен екземпляр перечитує його не частіше ніж раз на 5 с."""
    global _flag_value, _flag_checked_at
    r = client()
    if r is None:
        return False
    now = time.monotonic()
    if _flag_value is None or now - _flag_checked_at > FLAG_REFRESH_SECONDS:
        _flag_checked_at = now
        try:
            raw = r.get(FLAG_KEY)
            _flag_value = get_settings().cache_enabled if raw is None else raw == b"1"
        except redis.RedisError as exc:
            log.warning("Redis unavailable: %s", exc.__class__.__name__)
            _flag_value = False
    return _flag_value


def set_enabled(value: bool) -> None:
    global _flag_value
    r = client()
    if r is None:
        raise RuntimeError("Redis is not configured")
    r.set(FLAG_KEY, "1" if value else "0")
    _flag_value = value


def get(key: str) -> bytes | None:
    try:
        value = client().get(key)
        client().hincrby(STATS_KEY, "hits" if value is not None else "misses", 1)
        return value
    except redis.RedisError as exc:
        log.warning("Redis GET failed: %s", exc.__class__.__name__)
        return None


def put(key: str, value: bytes, ttl: int | None = None) -> None:
    if client() is None:
        return
    try:
        client().set(key, value, ex=ttl or get_settings().cache_ttl_seconds)
    except redis.RedisError as exc:
        log.warning("Redis SET failed: %s", exc.__class__.__name__)


def stats() -> dict:
    r = client()
    if r is None:
        return {"configured": False}
    raw = {k.decode(): int(v) for k, v in r.hgetall(STATS_KEY).items()}
    hits, misses = raw.get("hits", 0), raw.get("misses", 0)
    total = hits + misses
    return {
        "configured": True,
        "enabled": enabled(),
        "ttl_seconds": get_settings().cache_ttl_seconds,
        "hits": hits,
        "misses": misses,
        "hit_ratio": round(hits / total, 4) if total else None,
    }


def reset_stats() -> None:
    r = client()
    if r is not None:
        r.delete(STATS_KEY)
