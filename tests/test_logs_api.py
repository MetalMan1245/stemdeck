from __future__ import annotations

import io
import zipfile

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(tmp_path, monkeypatch):
    from app import main as main_mod

    monkeypatch.setattr(main_mod, "LOGS_DIR", tmp_path / "logs")
    return TestClient(main_mod.app)


@pytest.fixture
def logs_dir(tmp_path):
    d = tmp_path / "logs"
    d.mkdir(parents=True, exist_ok=True)
    return d


# --- GET /api/logs ---------------------------------------------------------


def test_reports_the_log_directory(client, logs_dir):
    body = client.get("/api/logs").json()
    assert body["dir"] == str(logs_dir.resolve())
    assert body["dir_exists"] is True


def test_reports_a_missing_directory_without_failing(client, tmp_path):
    """A fresh install has written nothing yet; the tab must still render."""
    body = client.get("/api/logs").json()
    assert body["dir_exists"] is False
    assert all(f["exists"] is False for f in body["files"])


def test_marks_existing_files_with_size(client, logs_dir):
    (logs_dir / "stemdeck.log").write_text("hello", encoding="utf-8")
    files = {f["name"]: f for f in client.get("/api/logs").json()["files"]}
    assert files["stemdeck.log"]["exists"] is True
    assert files["stemdeck.log"]["size"] == 5
    assert files["stemdeck.log"]["modified"] is not None
    assert files["stemdeck.log.1"]["exists"] is False


def test_every_file_is_described(client, logs_dir):
    for f in client.get("/api/logs").json()["files"]:
        assert f["description"], f["name"]


def test_covers_rotations_and_the_desktop_logs(client, logs_dir):
    names = {f["name"] for f in client.get("/api/logs").json()["files"]}
    assert {"stemdeck.log", "stemdeck.log.1", "stemdeck.log.2", "stemdeck.log.3"} <= names
    # Written by the Tauri shell, so absent on server deployments but still
    # worth listing so a desktop user knows where to look.
    assert {"backend.log", "backend.log.1", "backend.log.2", "setup.log"} <= names


def test_never_returns_log_contents(client, logs_dir):
    """Metadata only: a traceback can capture anything, and serving it over
    HTTP would widen that to whoever can reach the app."""
    (logs_dir / "stemdeck.log").write_text("SECRET-TOKEN-abc123", encoding="utf-8")
    assert "SECRET-TOKEN" not in client.get("/api/logs").text


# --- GET /api/logs.zip -----------------------------------------------------


def _names(resp):
    with zipfile.ZipFile(io.BytesIO(resp.content)) as z:
        return set(z.namelist())


def test_zip_bundles_every_present_log(client, logs_dir):
    (logs_dir / "stemdeck.log").write_text("current", encoding="utf-8")
    (logs_dir / "stemdeck.log.1").write_text("older", encoding="utf-8")
    (logs_dir / "setup.log").write_text("setup", encoding="utf-8")
    r = client.get("/api/logs.zip")
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/zip"
    assert _names(r) == {"stemdeck.log", "stemdeck.log.1", "setup.log"}


def test_zip_preserves_contents(client, logs_dir):
    (logs_dir / "stemdeck.log").write_text("line one\nline two\n", encoding="utf-8")
    with zipfile.ZipFile(io.BytesIO(client.get("/api/logs.zip").content)) as z:
        assert z.read("stemdeck.log").decode() == "line one\nline two\n"


def test_zip_only_includes_known_log_names(client, logs_dir):
    """The name set is fixed, so anything else dropped in the directory -- a
    stray dump, an editor swap file -- can never be swept into a download."""
    (logs_dir / "stemdeck.log").write_text("ok", encoding="utf-8")
    (logs_dir / "credentials.txt").write_text("do not ship me", encoding="utf-8")
    (logs_dir / "notes.log").write_text("nor me", encoding="utf-8")
    assert _names(client.get("/api/logs.zip")) == {"stemdeck.log"}


def test_zip_explains_itself_when_there_is_nothing_to_send(client, logs_dir):
    """An empty zip reads as a broken download; say why instead."""
    names = _names(client.get("/api/logs.zip"))
    assert names == {"README.txt"}


def test_zip_survives_a_missing_directory(client, tmp_path):
    r = client.get("/api/logs.zip")
    assert r.status_code == 200
    assert _names(r) == {"README.txt"}


def test_zip_filename_is_timestamped(client, logs_dir):
    (logs_dir / "stemdeck.log").write_text("x", encoding="utf-8")
    cd = client.get("/api/logs.zip").headers["content-disposition"]
    assert cd.startswith('attachment; filename="stemdeck-logs-')
    assert cd.endswith('.zip"')


def test_zip_skips_an_unreadable_file_rather_than_failing(client, logs_dir, monkeypatch):
    """One bad file must not lose the rest of the bundle."""
    (logs_dir / "stemdeck.log").write_text("good", encoding="utf-8")
    (logs_dir / "setup.log").write_text("bad", encoding="utf-8")

    real = type(logs_dir).read_bytes

    def _boom(self):
        if self.name == "setup.log":
            raise OSError("permission denied")
        return real(self)

    monkeypatch.setattr(type(logs_dir), "read_bytes", _boom)
    assert _names(client.get("/api/logs.zip")) == {"stemdeck.log"}
