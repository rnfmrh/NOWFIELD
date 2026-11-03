import os
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

load_dotenv()

DEFAULT_MYSQL_URL = "mysql+pymysql://root:@localhost:3306/nowfield?charset=utf8mb4"
DATABASE_URL = os.getenv("DATABASE_URL", DEFAULT_MYSQL_URL)

# Connection arguments (SQLite needs check_same_thread; MySQL uses pooling)
connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(
    DATABASE_URL,
    connect_args=connect_args,
    pool_pre_ping=True,
    pool_recycle=3600,
    echo=False
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
