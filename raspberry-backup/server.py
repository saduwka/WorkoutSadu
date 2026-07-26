#!/usr/bin/env python3
"""Minimal WorkoutSadu home backup receiver for Raspberry Pi."""

from __future__ import annotations

import json
import os
import shutil
from datetime import date, datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

DATA_DIR = Path(os.environ.get("BACKUP_DATA_DIR", "/data"))
ARCHIVE_DIR = DATA_DIR / "archive"
TOKEN = os.environ.get("BACKUP_TOKEN", "").strip()
PORT = int(os.environ.get("BACKUP_PORT", "8787"))
RETENTION_DAYS = int(os.environ.get("BACKUP_RETENTION_DAYS", "30"))
MAX_BODY = 20 * 1024 * 1024  # 20 MB


def ensure_dirs() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)


def prune_archives() -> None:
    cutoff = date.today().toordinal() - RETENTION_DAYS
    for path in ARCHIVE_DIR.glob("backup-*.json"):
        stem = path.stem  # backup-YYYY-MM-DD
        try:
            d = date.fromisoformat(stem.removeprefix("backup-"))
        except ValueError:
            continue
        if d.toordinal() < cutoff:
            path.unlink(missing_ok=True)


def authorize(handler: BaseHTTPRequestHandler) -> bool:
    if not TOKEN:
        handler.send_error(500, "BACKUP_TOKEN is not configured")
        return False
    header = handler.headers.get("Authorization", "")
    if header != f"Bearer {TOKEN}":
        handler.send_error(401, "Unauthorized")
        return False
    return True


def send_json(handler: BaseHTTPRequestHandler, code: int, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class BackupHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        print(f"[backup] {self.address_string()} - {fmt % args}")

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            send_json(self, 200, {"ok": True, "service": "workout-sadu-backup"})
            return
        self.send_error(404, "Not found")

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path != "/backup":
            self.send_error(404, "Not found")
            return
        if not authorize(self):
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BODY:
            self.send_error(400, "Invalid Content-Length")
            return

        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.send_error(400, "Body must be valid JSON")
            return

        if not isinstance(payload, dict):
            self.send_error(400, "JSON root must be an object")
            return

        ensure_dirs()
        latest = DATA_DIR / "latest.json"
        tmp = DATA_DIR / "latest.json.tmp"
        tmp.write_bytes(raw)
        tmp.replace(latest)

        today = date.today().isoformat()
        archive = ARCHIVE_DIR / f"backup-{today}.json"
        shutil.copy2(latest, archive)
        prune_archives()

        send_json(
            self,
            200,
            {
                "ok": True,
                "saved": "latest.json",
                "archive": archive.name,
                "bytes": length,
                "receivedAt": datetime.now(timezone.utc).isoformat(),
            },
        )


def main() -> None:
    if not TOKEN:
        raise SystemExit("BACKUP_TOKEN env var is required")
    ensure_dirs()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), BackupHandler)
    print(f"[backup] listening on 0.0.0.0:{PORT}, data={DATA_DIR}")
    server.serve_forever()


if __name__ == "__main__":
    main()
