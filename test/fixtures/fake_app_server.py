#!/usr/bin/env python3
import json
import os
import sys
import threading
import time

MODE = os.environ.get("FAKE_CODEX_MODE", "complete")
THREAD_ID = "thr_fixture"
TURN_COUNTER = 0
ACTIVE_TURN = None
INTERRUPTED = threading.Event()


def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def send_completed(turn_id, status="completed"):
    send({"method": "turn/completed", "params": {"turn": {"id": turn_id, "status": status}}})


def handle_turn(turn_id):
    if MODE == "approval":
      send({"id": 900, "method": "item/commandExecution/requestApproval", "params": {"threadId": THREAD_ID, "turnId": turn_id}})
    elif MODE == "user_input":
      send({"id": 901, "method": "item/tool/requestUserInput", "params": {"threadId": THREAD_ID, "turnId": turn_id, "itemId": "item_1", "questions": []}})
    elif MODE == "task_complete":
      send({"method": "codex/event/task_complete", "params": {"id": turn_id, "msg": {"type": "task_complete", "last_agent_message": "done"}}})
    elif MODE == "interrupt":
      while not INTERRUPTED.is_set():
        time.sleep(0.05)
      send_completed(turn_id, "interrupted")
      return

    time.sleep(0.05)
    send_completed(turn_id, "completed")


for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue

    msg = json.loads(raw)
    if msg.get("method") == "initialize":
        send({"id": msg["id"], "result": {"serverInfo": {"name": "fake"}}})
    elif msg.get("method") == "thread/start":
        send({"id": msg["id"], "result": {"thread": {"id": THREAD_ID}}})
        send({"method": "thread/started", "params": {"thread": {"id": THREAD_ID}}})
    elif msg.get("method") == "turn/start":
        TURN_COUNTER += 1
        ACTIVE_TURN = f"turn_{TURN_COUNTER}"
        send({"id": msg["id"], "result": {"turn": {"id": ACTIVE_TURN, "status": "inProgress", "items": [], "error": None}}})
        send({"method": "turn/started", "params": {"turn": {"id": ACTIVE_TURN, "status": "inProgress"}}})
        threading.Thread(target=handle_turn, args=(ACTIVE_TURN,), daemon=True).start()
    elif msg.get("method") == "turn/interrupt":
        INTERRUPTED.set()
        send({"id": msg["id"], "result": {}})
    elif "id" in msg and "result" in msg:
        send({"method": "serverRequest/resolved", "params": {"threadId": THREAD_ID, "requestId": msg["id"]}})
        if MODE == "approval":
            send_completed(ACTIVE_TURN, "completed")
        elif MODE == "user_input":
            send_completed(ACTIVE_TURN, "failed")
    elif "id" in msg and "error" in msg:
        send({"method": "serverRequest/resolved", "params": {"threadId": THREAD_ID, "requestId": msg["id"]}})
        if MODE == "user_input":
            send_completed(ACTIVE_TURN, "failed")
