"""The async engine, the session factory and the get_db dependency used by the routers."""

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import declarative_base

from app.config import settings

DATABASE_URL = settings.DB_CONN_STR

# the engine logs every statement it runs, but only when the log level is DEBUG
engine = create_async_engine(DATABASE_URL, echo=settings.LOG_LEVEL == "DEBUG")

AsyncSessionLocal = async_sessionmaker(
    bind=engine, class_=AsyncSession, expire_on_commit=False
)

Base = declarative_base()


async def get_db():
    """Yield a session, commit it on success, roll it back on error, always close it."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
