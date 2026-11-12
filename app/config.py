from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "books"
    db_user: str = "books"
    db_password: str = ""
    db_sslmode: str = "prefer"

    auth_enabled: bool = False
    cognito_region: str = ""
    cognito_user_pool_id: str = ""
    cognito_client_id: str = ""

    # Redis: порожній redis_host вимикає і кеш, і ідемпотентність
    redis_host: str = ""
    redis_port: int = 6379
    cache_enabled: bool = True
    cache_ttl_seconds: int = 30
    idempotency_ttl_seconds: int = 24 * 3600

    # SQS: асинхронне створення книг (POST /books/async → черга → app.worker)
    aws_region: str = "eu-north-1"
    sqs_queue_url: str = ""
    sqs_endpoint_url: str = ""  # локально — ElasticMQ; у хмарі порожньо
    worker_work_seconds: float = 0.1  # імітація тривалої обробки одного повідомлення

    @property
    def cognito_issuer(self) -> str:
        return f"https://cognito-idp.{self.cognito_region}.amazonaws.com/{self.cognito_user_pool_id}"


@lru_cache
def get_settings() -> Settings:
    return Settings()
