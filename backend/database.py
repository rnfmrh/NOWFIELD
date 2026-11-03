import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.orm import declarative_base, sessionmaker

load_dotenv()

DEFAULT_MYSQL_URL = "mysql+pymysql://root:@localhost:3306/nowfield?charset=utf8mb4"
SQLITE_FALLBACK_URL = "sqlite:///./nowfield.db"


def _resolve_engine():
    env_url = os.getenv("DATABASE_URL")
    target_url = env_url or DEFAULT_MYSQL_URL

    if target_url.startswith("sqlite"):
        return create_engine(
            target_url,
            connect_args={"check_same_thread": False},
            pool_pre_ping=True,
            echo=False,
        )

    try:
        eng = create_engine(
            target_url,
            pool_pre_ping=True,
            pool_recycle=3600,
            echo=False,
        )
        with eng.connect() as conn:
            conn.execute(text("SELECT 1"))
        return eng
    except Exception as e:
        print(f"[DB Notice] MySQL connection unavailable ({e}). Falling back to SQLite ({SQLITE_FALLBACK_URL}).")
        return create_engine(
            SQLITE_FALLBACK_URL,
            connect_args={"check_same_thread": False},
            pool_pre_ping=True,
            echo=False,
        )


engine = _resolve_engine()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
