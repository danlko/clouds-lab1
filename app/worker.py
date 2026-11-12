"""Обробник черги: python -m app.worker

Читає SQS (long polling), для кожного повідомлення створює книгу і видаляє повідомлення.
Доставка «щонайменше один раз»: якщо обробник упаде після commit, але до DeleteMessage,
повідомлення повернеться після visibility timeout. Повтор нейтралізує первинний ключ operations.id:
INSERT … ON CONFLICT DO NOTHING у тій самій транзакції, що й INSERT книги.
"""
import json
import logging
import signal
import time

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import OperationalError

from . import models
from .config import get_settings
from .db import Base, SessionLocal, engine
from .queue import sqs

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s worker: %(message)s")
log = logging.getLogger("worker")

stopping = False


def _stop(signum, _frame):
    global stopping
    log.info("signal %s: finishing current batch and exiting", signum)
    stopping = True


def process(body: dict) -> bool:
    """True — книгу створено; False — повторна доставка, нічого не зроблено."""
    time.sleep(get_settings().worker_work_seconds)  # «тривала» частина (зовнішній виклик, обробка)
    with SessionLocal() as db, db.begin():
        claimed = db.execute(
            insert(models.Operation)
            .values(id=body["operation_id"])
            .on_conflict_do_nothing(index_elements=["id"])
            .returning(models.Operation.id)
        ).first()
        if claimed is None:
            return False
        book = models.Book(**body["payload"])
        db.add(book)
        db.flush()
        db.get(models.Operation, body["operation_id"]).book_id = book.id
    return True


def main() -> None:
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    s = get_settings()
    for attempt in range(1, 31):
        try:
            Base.metadata.create_all(engine)
            break
        except OperationalError:
            log.warning("DB not ready (attempt %s/30)", attempt)
            time.sleep(2)

    log.info("polling %s", s.sqs_queue_url)
    while not stopping:
        resp = sqs().receive_message(
            QueueUrl=s.sqs_queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=20,
            AttributeNames=["ApproximateReceiveCount"],
        )
        for msg in resp.get("Messages", []):
            body = json.loads(msg["Body"])
            receives = msg["Attributes"]["ApproximateReceiveCount"]
            try:
                created = process(body)
            except Exception:
                # не видаляємо: повідомлення повернеться в чергу, після 5 спроб — у DLQ
                log.exception("operation %s failed (receive #%s)", body.get("operation_id"), receives)
                continue
            if not created:
                log.info("operation %s already processed (receive #%s) — duplicate skipped", body["operation_id"], receives)
            sqs().delete_message(QueueUrl=s.sqs_queue_url, ReceiptHandle=msg["ReceiptHandle"])
    log.info("stopped")


if __name__ == "__main__":
    main()
