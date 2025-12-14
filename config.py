import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    # Основная база данных
    SQLALCHEMY_DATABASE_URI = os.getenv(
        'DATABASE_URL', 
        'postgresql+psycopg://postgres:password@localhost:5432/subscriptions_db'
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key')