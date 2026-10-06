from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class BookCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    author: str = Field(min_length=1, max_length=200)
    year: int | None = Field(default=None, ge=0, le=2100)


class BookRead(BookCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
