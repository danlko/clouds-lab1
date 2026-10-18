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

    @property
    def cognito_issuer(self) -> str:
        return f"https://cognito-idp.{self.cognito_region}.amazonaws.com/{self.cognito_user_pool_id}"


@lru_cache
def get_settings() -> Settings:
    return Settings()
