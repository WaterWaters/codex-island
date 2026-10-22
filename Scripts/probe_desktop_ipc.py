#!/usr/bin/env python3
"""Read-only capability probe. Never prints identifiers or conversation payloads."""
import json
import os
import socket
import sqlite3
import struct
import time
import uuid


def main():
    report = {"transport": "desktop-ipc", "initialized": False,
              "followingReplies": 0, "snapshotCount": 0, "stateFields": [],
              "runtimeTypes": [], "error": None}
    client = "codex-island-probe"
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.settimeout(3)

    def send(message):
        payload = json.dumps(message).encode()
        conn.sendall(struct.pack("<I", len(payload)) + payload)

    def exact(count):
        result = bytearray()
        while len(result) < count:
            part = conn.recv(count - len(result))
            if not part:
                raise EOFError()
            result.extend(part)
        return result

    def receive():
        size = struct.unpack("<I", exact(4))[0]
        if not 0 < size <= 8 * 1024 * 1024:
            raise ValueError("frame-size")
        message = json.loads(exact(size))
        if message.get("type") == "client-discovery-request":
            send({"type": "client-discovery-response",
                  "requestId": message.get("requestId"), "response": {"canHandle": False}})
        return message

    def broadcast(method, params):
        send({"type": "broadcast", "method": method, "version": 1,
              "sourceClientId": client, "params": params})

    subscriptions = set()
    try:
        conn.connect(os.path.expanduser("~/.codex/ipc/ipc.sock"))
        request_id = str(uuid.uuid4())
        send({"type": "request", "requestId": request_id, "sourceClientId": client,
              "version": 0, "method": "initialize", "params": {"clientType": "codex-island"}})
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            message = receive()
            if message.get("requestId") != request_id or message.get("type") != "response":
                continue
            result = message.get("result", {})
            if message.get("resultType") != "success" or not result.get("clientId"):
                raise ValueError("initialize-rejected")
            client = result["clientId"]
            report["initialized"] = True
            break
        if not report["initialized"]:
            raise TimeoutError()
        # Current builds require an explicit conversation and host. The empty
        # request used by older community clients produces no replies.
        database = os.path.expanduser("~/.codex/state_5.sqlite")
        with sqlite3.connect("file:" + database + "?mode=ro", uri=True) as db:
            candidates = db.execute("SELECT id FROM threads WHERE archived=0 AND (agent_path IS NULL OR agent_path='/root') AND CASE WHEN json_valid(source) THEN json_type(source,'$.subagent') IS NULL ELSE 1 END ORDER BY updated_at DESC LIMIT 12").fetchall()
        for (thread,) in candidates:
            key = ("local", thread)
            subscriptions.add(key)
            broadcast("thread-stream-following-status-requested", {
                "hostId": key[0], "conversationId": key[1]})
            broadcast("thread-stream-following-changed", {
                "hostId": key[0], "conversationId": key[1], "following": True})
        deadline = time.monotonic() + 8
        fields, runtimes = set(), set()
        while time.monotonic() < deadline:
            conn.settimeout(max(0.1, deadline - time.monotonic()))
            message = receive()
            params = message.get("params", {})
            method = message.get("method")
            if method == "thread-stream-following-changed":
                report["followingReplies"] += 1
                key = (params.get("hostId"), params.get("conversationId"))
                if params.get("following") and all(key) and key not in subscriptions:
                    subscriptions.add(key)
                    broadcast("thread-stream-following-changed", {
                        "hostId": key[0], "conversationId": key[1], "following": True})
            if method == "thread-stream-state-changed":
                change = params.get("change", {})
                state = change.get("conversationState", {})
                if change.get("type") != "snapshot":
                    continue
                report["snapshotCount"] += 1
                fields.update(k for k in ["threadRuntimeStatus", "hasUnreadTurn", "requests", "error"] if k in state)
                runtime = state.get("threadRuntimeStatus", {}).get("type")
                if runtime in ["active", "idle", "notLoaded", "systemError"]:
                    runtimes.add(runtime)
                report["stateFields"] = sorted(fields)
                report["runtimeTypes"] = sorted(runtimes)
    except socket.timeout:
        if not report["initialized"]:
            report["error"] = "timeout"
    except (OSError, EOFError, ValueError, TypeError, AttributeError, sqlite3.Error) as error:
        report["error"] = type(error).__name__
        if isinstance(error, OSError):
            report["errno"] = error.errno
    finally:
        for host, thread in subscriptions:
            try:
                broadcast("thread-stream-following-changed", {
                    "hostId": host, "conversationId": thread, "following": False})
            except OSError:
                break
        conn.close()
    report["compatible"] = report["initialized"] and report["snapshotCount"] > 0
    print(json.dumps(report, indent=2))
    return 0 if report["compatible"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
