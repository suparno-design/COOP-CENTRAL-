import os

DB = {
    "host": os.getenv("DB_HOST", "localhost"),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", "your_password"),
    "database": os.getenv("DB_NAME", "coop_central"),
}
SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-change-me")
