"""Відправка повідомлень у SQS."""
import json
from functools import lru_cache

import boto3

from .config import get_settings


@lru_cache
def sqs():
    s = get_settings()
    return boto3.client("sqs", region_name=s.aws_region, endpoint_url=s.sqs_endpoint_url or None)


def configured() -> bool:
    return bool(get_settings().sqs_queue_url)


def send(message: dict) -> None:
    sqs().send_message(QueueUrl=get_settings().sqs_queue_url, MessageBody=json.dumps(message))
