"""Tiny Lambda that stands in for the thing being deployed.

It reports which environment and build it is running, and can write/read one
item in its DynamoDB table so the smoke test proves the wiring end to end.
"""

import json
import os
import time

_table = None


def _get_table():
    global _table
    if _table is None:
        import boto3  # available in the Lambda runtime; not needed for unit tests

        _table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    return _table


def handler(event, context=None, table=None):
    event = event or {}
    action = event.get("action", "health")
    env = os.environ.get("APP_ENV", "local")
    build = os.environ.get("BUILD_SHA", "dev-local")

    if action == "health":
        return {"status": "ok", "env": env, "build": build}

    if action in ("put", "get"):
        item_id = event.get("id")
        if not item_id:
            return {"status": "error", "error": "id is required"}
        tbl = table or _get_table()
        if action == "put":
            item = {"id": str(item_id), "value": json.dumps(event.get("value")), "build": build, "ts": int(time.time())}
            tbl.put_item(Item=item)
            return {"status": "ok", "item": item}
        found = tbl.get_item(Key={"id": str(item_id)}).get("Item")
        return {"status": "ok" if found else "not_found", "item": found}

    return {"status": "error", "error": f"unknown action: {action}"}
