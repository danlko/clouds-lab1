import logging
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Response, status
from sqlalchemy import select, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from . import models
from .auth import require_user
from .db import Base, engine, get_db
from .schemas import BookCreate, BookRead

log = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Створюємо таблиці при старті; чекаємо на БД, якщо вона ще піднімається
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
    version="1.0.0",
    description="Лабораторна 1: REST API у контейнері на AWS (ECS Fargate + RDS + ALB). "
    "Читання — публічне, зміна даних — лише з Bearer JWT (Cognito).",
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
def list_books(db: Session = Depends(get_db)):
    return db.scalars(select(models.Book).order_by(models.Book.id)).all()


@app.get("/books/{book_id}", response_model=BookRead, tags=["books"])
def get_book(book_id: int, db: Session = Depends(get_db)):
    book = db.get(models.Book, book_id)
    if book is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Book not found")
    return book


@app.post(
    "/books",
    response_model=BookRead,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_user)],
    tags=["books"],
)
def create_book(payload: BookCreate, db: Session = Depends(get_db)):
    book = models.Book(**payload.model_dump())
    db.add(book)
    db.commit()
    return book


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
