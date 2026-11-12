"""Імітація повторної доставки: те саме повідомлення двічі в черзі → одна книга.

Запуск локально (compose):  docker compose cp tests worker:/app/tests && docker compose exec -e PYTHONPATH=/app worker python tests/test_queue_redelivery.py
"""
import time
import uuid

from sqlalchemy import func, select

from app import models
from app.db import SessionLocal
from app.queue import send


def test_duplicate_message_creates_one_book():
    op_id = str(uuid.uuid4())
    author = f"redelivery-{op_id[:8]}"
    msg = {"operation_id": op_id, "user_sub": "test", "payload": {"title": "Dup", "author": author, "year": 2020}}
    send(msg)
    send(msg)  # друга доставка того самого повідомлення
    for _ in range(30):
        time.sleep(1)
        with SessionLocal() as db:
            if db.get(models.Operation, op_id) is not None:
                break
    time.sleep(2)  # дати обробнику прочитати і дубль
    with SessionLocal() as db:
        count = db.scalar(select(func.count()).select_from(models.Book).where(models.Book.author == author))
    assert count == 1, count
    print(f"OK: operation {op_id} delivered twice, books by {author}: {count}")


if __name__ == "__main__":
    test_duplicate_message_creates_one_book()
