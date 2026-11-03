"""Shared PostgreSQL connection for every Lambda that talks to RDS."""
import json
import os
import ssl

import boto3
import pg8000.dbapi

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "penguistics")
DB_SECRET_ARN = os.environ.get("DB_SECRET_ARN")
LOCAL_HOSTS = ("localhost", "127.0.0.1")

_db_connection = None


def get_credentials() -> tuple[str, str]:
    """Read the RDS-managed secret. Only a local database may use DB_USER/DB_PASSWORD."""
    if DB_SECRET_ARN:
        secret = boto3.client("secretsmanager").get_secret_value(SecretId=DB_SECRET_ARN)
        values = json.loads(secret["SecretString"])
        return values["username"], values["password"]
    if DB_HOST not in LOCAL_HOSTS:
        raise RuntimeError("DB_SECRET_ARN must be set to connect to a remote database.")
    return os.environ.get("DB_USER", "postgres"), os.environ.get("DB_PASSWORD", "")


def connect():
    """Open a new connection. RDS rotates the password, so credentials are read fresh each time."""
    user, password = get_credentials()
    ssl_ctx = None
    if DB_HOST not in LOCAL_HOSTS:
        ssl_ctx = ssl.create_default_context()
        ssl_ctx.check_hostname = False
        ssl_ctx.verify_mode = ssl.CERT_NONE

    return pg8000.dbapi.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=user,
        password=password,
        ssl_context=ssl_ctx,
    )


def get_db_connection():
    """Return a reusable PostgreSQL connection across warm Lambda invocations."""
    global _db_connection
    if _db_connection is None:
        _db_connection = connect()
    return _db_connection
