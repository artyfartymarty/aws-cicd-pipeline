import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import handler as h  # noqa: E402


class FakeTable:
    def __init__(self):
        self.items = {}

    def put_item(self, Item):
        self.items[Item["id"]] = Item

    def get_item(self, Key):
        item = self.items.get(Key["id"])
        return {"Item": item} if item else {}


def test_health_reports_env_and_build(monkeypatch):
    monkeypatch.setenv("APP_ENV", "dev")
    monkeypatch.setenv("BUILD_SHA", "abc123")
    assert h.handler({"action": "health"}) == {"status": "ok", "env": "dev", "build": "abc123"}


def test_default_action_is_health():
    assert h.handler({})["status"] == "ok"


def test_put_then_get_roundtrip():
    t = FakeTable()
    put = h.handler({"action": "put", "id": "1", "value": {"a": 1}}, table=t)
    assert put["status"] == "ok"
    got = h.handler({"action": "get", "id": "1"}, table=t)
    assert got["item"]["value"] == '{"a": 1}'


def test_get_missing_item():
    assert h.handler({"action": "get", "id": "nope"}, table=FakeTable())["status"] == "not_found"


def test_put_requires_id():
    assert h.handler({"action": "put"}, table=FakeTable())["status"] == "error"


def test_unknown_action():
    assert h.handler({"action": "explode"})["status"] == "error"
