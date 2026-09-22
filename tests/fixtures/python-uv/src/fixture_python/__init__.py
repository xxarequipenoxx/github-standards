"""Fixture package: one query executed on SQLite or PostgreSQL."""

from __future__ import annotations

import os
import sqlite3

QUERY = "SELECT 1 + 1"


def database_url() -> str | None:
    """Return the PostgreSQL URL exported by the CI workflow, if any."""
    return os.environ.get("TEST_DATABASE_URL")


def two() -> int:
    """Compute 1 + 1 on PostgreSQL when a database URL is set, on SQLite otherwise."""
    url = database_url()
    if url:
        import psycopg

        with psycopg.connect(url) as connection:
            row = connection.execute(QUERY).fetchone()
    else:
        with sqlite3.connect(":memory:") as connection:
            row = connection.execute(QUERY).fetchone()
    if row is None:
        raise RuntimeError("the query returned no row")
    return int(row[0])
