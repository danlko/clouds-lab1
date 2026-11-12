import json
import logging
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Response, status
from pydantic import TypeAdapter
from sqlalchemy import func, select, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from . import cache, idempotency, models, queue
from .auth import require_user
from .config import get_settings
from .db import Base, engine, get_db
from .schemas import AuthorRead, BookCreate, BookRead, OperationAccepted, OperationStatus

books_json = TypeAdapter(list[BookRead])

log = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(_: FastAPI):
    for attempt in range(1, 31):
        try:
            Base.metadata.create_all(engine)
            break
        except OperationalError as exc:
            log.warning("DB not ready (attempt %s/30): %s", attempt, exc.__class__.__name__)
            time.sleep(2)
    else:
        raise RuntimeError("Database is not reachable")
    yield


app = FastAPI(
    title="Books API",
    version="2.0.0",
    description="REST API у контейнері на AWS (ECS Fargate + RDS + ALB + Redis). "
    "Читання — публічне, зміна даних — лише з Bearer JWT (Cognito). "
    "Список книг кешується в Redis (cache-aside).",
    lifespan=lifespan,
)


@app.get("/health", tags=["service"])
def health():
    """Liveness — використовується health check'ом ALB."""
    return {"status": "ok"}


@app.get("/health/db", tags=["service"])
def health_db(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "up"}


@app.get("/me", tags=["service"])
def me(claims: dict = Depends(require_user)):
    """Захищений ендпоінт: показує, хто автентифікований."""
    return {"sub": claims.get("sub"), "username": claims.get("username")}


@app.get("/books", response_model=list[BookRead], tags=["books"])
def list_books(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """Найновіші книги. Cache-aside: Redis → (промах) БД → Redis з TTL. Заголовок X-Cache: HIT/MISS/BYPASS."""
    use_cache = cache.enabled()
    key = f"{cache.LIST_PREFIX}{limit}:{offset}"
    if use_cache and (cached := cache.get(key)) is not None:
        return Response(cached, media_type="application/json", headers={"X-Cache": "HIT"})

    books = db.scalars(select(models.Book).order_by(models.Book.id.desc()).limit(limit).offset(offset)).all()
    body = books_json.dump_json(books_json.validate_python(books, from_attributes=True))
    if use_cache:
        cache.put(key, body)
    return Response(body, media_type="application/json", headers={"X-Cache": "MISS" if use_cache else "BYPASS"})


@app.get("/books/{book_id}", response_model=BookRead, tags=["books"])
def get_book(book_id: int, db: Session = Depends(get_db)):
    book = db.get(models.Book, book_id)
    if book is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Book not found")
    return book


@app.get("/authors/{author}", response_model=AuthorRead, tags=["books"])
def get_author(author: str, db: Session = Depends(get_db)):
    """Дані автора: кількість книг і 10 найновіших."""
    total = db.scalar(select(func.count()).select_from(models.Book).where(models.Book.author == author))
    if not total:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Author not found")
    latest = db.scalars(
        select(models.Book).where(models.Book.author == author).order_by(models.Book.id.desc()).limit(10)
    ).all()
    return AuthorRead(author=author, books_count=total, latest_books=[BookRead.model_validate(b) for b in latest])


@app.post(
    "/books",
    response_model=BookRead,
    status_code=status.HTTP_201_CREATED,
    tags=["books"],
)
def create_book(
    payload: BookCreate,
    db: Session = Depends(get_db),
    claims: dict = Depends(require_user),
    idempotency_key: str | None = Header(None, alias="Idempotency-Key", max_length=128),
):
    """З заголовком Idempotency-Key повторний запит повертає збережену відповідь (24 год) без нового запису."""

    def execute() -> tuple[int, str]:
        book = models.Book(**payload.model_dump())
        db.add(book)
        db.commit()
        return status.HTTP_201_CREATED, BookRead.model_validate(book).model_dump_json()

    if idempotency_key:
        return idempotency.run_once(claims["sub"], idempotency_key, payload.model_dump_json(), execute)
    status_code, body = execute()
    return Response(body, status_code=status_code, media_type="application/json")


@app.post(
    "/books/async",
    response_model=OperationAccepted,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["queue"],
)
def create_book_async(
    payload: BookCreate,
    claims: dict = Depends(require_user),
    idempotency_key: str | None = Header(None, alias="Idempotency-Key", max_length=128),
):
    """Кладе операцію в SQS і одразу відповідає 202. Книгу створює app.worker;
    результат — GET /operations/{operation_id}. Підтримує Idempotency-Key (повтор не створює друге повідомлення)."""
    if not queue.configured():
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Queue is not configured")

    def execute() -> tuple[int, str]:
        op_id = str(uuid.uuid4())
        queue.send({"operation_id": op_id, "user_sub": claims.get("sub"), "payload": payload.model_dump()})
        cache.put(f"op:{op_id}", b"pending", ttl=get_settings().idempotency_ttl_seconds)
        body = OperationAccepted(operation_id=op_id, status="pending", status_url=f"/operations/{op_id}")
        return status.HTTP_202_ACCEPTED, body.model_dump_json()

    if idempotency_key:
        resp = idempotency.run_once(claims["sub"], idempotency_key, payload.model_dump_json(), execute)
    else:
        status_code, body = execute()
        resp = Response(body, status_code=status_code, media_type="application/json")
    resp.headers["Location"] = json.loads(resp.body)["status_url"]
    return resp


@app.get("/operations/{operation_id}", response_model=OperationStatus, tags=["queue"])
def get_operation(operation_id: str, db: Session = Depends(get_db)):
    """pending — повідомлення ще в черзі; done — книгу створено (повертається разом з книгою)."""
    op = db.get(models.Operation, operation_id)
    if op is not None:
        book = db.get(models.Book, op.book_id) if op.book_id else None
        return OperationStatus(
            operation_id=operation_id, status="done", book=BookRead.model_validate(book) if book else None
        )
    r = cache.client()
    if r is not None and r.exists(f"op:{operation_id}"):
        return OperationStatus(operation_id=operation_id, status="pending")
    raise HTTPException(status.HTTP_404_NOT_FOUND, "Operation not found")


@app.put(
    "/books/{book_id}",
    response_model=BookRead,
    dependencies=[Depends(require_user)],
    tags=["books"],
)
def update_book(book_id: int, payload: BookCreate, db: Session = Depends(get_db)):
    book = db.get(models.Book, book_id)
    if book is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Book not found")
    for key, value in payload.model_dump().items():
        setattr(book, key, value)
    db.commit()
    return book


@app.delete(
    "/books/{book_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_user)],
    tags=["books"],
)
def delete_book(book_id: int, db: Session = Depends(get_db)):
    book = db.get(models.Book, book_id)
    if book is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Book not found")
    db.delete(book)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/cache/stats", tags=["cache"])
def cache_stats(db: Session = Depends(get_db)):
    """Частка влучань у кеш (лічильники в Redis, спільні для всіх екземплярів) і лічильники PostgreSQL
    (кількість транзакцій і прочитаних рядків) — для оцінки навантаження на БД з кешем і без."""
    row = db.execute(
        text(
            "SELECT xact_commit, tup_returned, tup_fetched FROM pg_stat_database "
            "WHERE datname = current_database()"
        )
    ).one()
    return {
        "cache": cache.stats(),
        "db": {"xact_commit": row.xact_commit, "tup_returned": row.tup_returned, "tup_fetched": row.tup_fetched},
    }


@app.put("/admin/cache", dependencies=[Depends(require_user)], tags=["cache"])
def toggle_cache(enabled: bool, reset_stats: bool = True):
    """Увімкнути/вимкнути кеш для всіх екземплярів без передеплою (діє протягом ≤5 с)."""
    try:
        cache.set_enabled(enabled)
        if reset_stats:
            cache.reset_stats()
    except RuntimeError as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc))
    return cache.stats()
