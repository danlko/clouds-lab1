from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import get_settings

_s = get_settings()

DATABASE_URL = URL.create(
    "postgresql+psycopg",
    username=_s.db_user,
    password=_s.db_password,
    host=_s.db_host,
    port=_s.db_port,
    database=_s.db_name,
    query={"sslmode": _s.db_sslmode},
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
