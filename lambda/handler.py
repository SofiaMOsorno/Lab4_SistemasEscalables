import json
import os
import time
from datetime import datetime, timezone

import psycopg2
import redis


CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "300"))
REDIS_HOST = os.environ["REDIS_HOST"]
DATABASE_CONFIG = {
    "host": os.environ["DB_HOST"],
    "port": int(os.environ.get("DB_PORT", "5432")),
    "dbname": os.environ["DB_NAME"],
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
    "connect_timeout": 5,
}


def _timestamp():
    return datetime.now(timezone.utc).isoformat()


def _redis_client():
    return redis.Redis(
        host=REDIS_HOST,
        port=6379,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )


def _query_database():
    query_start = time.perf_counter()
    with psycopg2.connect(**DATABASE_CONFIG) as connection:
        with connection.cursor() as cursor:
            # The seed table keeps a fresh lab deployment immediately testable.
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS items (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            cursor.execute("SELECT COUNT(*) FROM items")
            if cursor.fetchone()[0] == 0:
                cursor.execute(
                    "INSERT INTO items (name) VALUES (%s), (%s), (%s)",
                    ("scalable-api", "redis-cache", "postgres-database"),
                )
            cursor.execute(
                "SELECT id, name, created_at FROM items ORDER BY id LIMIT 100"
            )
            rows = [
                {
                    "id": row[0],
                    "name": row[1],
                    "created_at": row[2].isoformat(),
                }
                for row in cursor.fetchall()
            ]
    query_ms = round((time.perf_counter() - query_start) * 1000, 2)
    print(json.dumps({"log": "DATABASE_QUERY", "query_time_ms": query_ms}))
    return rows, query_ms


def lambda_handler(event, context):
    request_id = context.aws_request_id
    request_timestamp = _timestamp()
    total_start = time.perf_counter()
    cache_key = "items:v1"
    cache_status = "HIT"
    query_time_ms = None

    try:
        cache = _redis_client()
        cached = cache.get(cache_key)
        if cached is not None:
            data = json.loads(cached)
            print(json.dumps({"log": "CACHE_HIT", "request_id": request_id}))
        else:
            cache_status = "MISS"
            print(json.dumps({"log": "CACHE_MISS", "request_id": request_id}))
            data, query_time_ms = _query_database()
            cache.setex(cache_key, CACHE_TTL_SECONDS, json.dumps(data))

        response_time_ms = round((time.perf_counter() - total_start) * 1000, 2)
        print(
            json.dumps(
                {
                    "log": "TOTAL_RESPONSE",
                    "request_id": request_id,
                    "response_time_ms": response_time_ms,
                    "timestamp": request_timestamp,
                }
            )
        )
        body = {
            "data": data,
            "response_time_ms": response_time_ms,
            "cache_status": cache_status,
            "timestamp": request_timestamp,
        }
        return {
            "statusCode": 200,
            "statusDescription": "200 OK",
            "isBase64Encoded": False,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(body),
        }
    except Exception as error:
        response_time_ms = round((time.perf_counter() - total_start) * 1000, 2)
        print(
            json.dumps(
                {
                    "log": "REQUEST_ERROR",
                    "request_id": request_id,
                    "error": str(error),
                    "response_time_ms": response_time_ms,
                    "timestamp": request_timestamp,
                }
            )
        )
        return {
            "statusCode": 500,
            "statusDescription": "500 Internal Server Error",
            "isBase64Encoded": False,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Internal server error", "request_id": request_id}),
        }
