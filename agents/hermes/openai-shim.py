#!/usr/bin/env python3
"""
Thin OpenAI-compatible HTTP shim in front of the Hermes CLI (issue: Open WebUI <-> Hermes).

hermes-agent has no HTTP agent API (its only HTTP server is the secrets-management
dashboard, deliberately not exposed). Open WebUI is already wired to try
http://hermes:8642/v1 as a second backend (see open-webui.yml OPENAI_API_BASE_URLS)
but nothing has ever listened there. This process is that listener: it shells out
to the real `hermes -z ... --cli --continue <session>` for every request and wraps
stdout in an OpenAI chat.completion(.chunk) envelope.

Session mapping (#31 groundwork): this stack is single-operator
(GATEWAY_ALLOW_ALL_USERS=true, one TELEGRAM_ALLOWED_USERS id) -- there is
really only one end user across every surface. So by default (HERMES_SHIM_
SESSION_MODE=unified, the default) every Open WebUI request continues the
SAME Hermes session (HERMES_SHIM_UNIFIED_SESSION, default "chairman-primary"),
giving one shared memory across all Open WebUI chats instead of one silo per
browser tab. Set HERMES_SHIM_SESSION_MODE=per-chat to fall back to the old
behavior (a session key hashed from each chat's first user message -- distinct
Open WebUI chats get distinct Hermes sessions, but nothing shares memory).
Full cross-surface (Telegram <-> Open WebUI) sync needs the Telegram platform
adapter's own session naming to align with this one -- not yet possible to
verify live (#27 blocks Telegram from connecting at all); see
docs/CONVERSATION_SYNC_DESIGN.md for the concrete plan once it does.

Internal-network-only: not published to the host, reachable only from other
containers on aef2_backend. No auth is enforced, matching the other internal-only
services on this network (mcp-*, etc.) -- this is a private compose network, not
an internet-facing one.
"""
import hashlib
import json
import os
import subprocess
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERMES_HOME = os.environ.get("HERMES_HOME", "/opt/data")
HERMES_BIN = "hermes"
CALL_TIMEOUT_S = 180
MODEL_ID = "hermes"
SESSION_MODE = os.environ.get("HERMES_SHIM_SESSION_MODE", "unified")
UNIFIED_SESSION = os.environ.get("HERMES_SHIM_UNIFIED_SESSION", "chairman-primary")


def session_key_for(messages):
    if SESSION_MODE != "per-chat":
        return UNIFIED_SESSION
    first_user = next((m.get("content", "") for m in messages if m.get("role") == "user"), "")
    if isinstance(first_user, list):  # some clients send content as parts
        first_user = " ".join(p.get("text", "") for p in first_user if isinstance(p, dict))
    digest = hashlib.sha1(first_user.encode("utf-8", "ignore")).hexdigest()[:16]
    return f"webui-{digest}"


def last_user_message(messages):
    for m in reversed(messages):
        if m.get("role") == "user":
            content = m.get("content", "")
            if isinstance(content, list):
                return " ".join(p.get("text", "") for p in content if isinstance(p, dict))
            return content
    return ""


def run_hermes(prompt, session):
    env = dict(os.environ)
    env["HOME"] = HERMES_HOME
    try:
        proc = subprocess.run(
            [HERMES_BIN, "-z", prompt, "--cli", "--continue", session],
            env=env,
            capture_output=True,
            text=True,
            timeout=CALL_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        return None, f"hermes call timed out after {CALL_TIMEOUT_S}s"
    if proc.returncode != 0:
        return None, f"hermes exited {proc.returncode}: {proc.stderr.strip()[:500]}"
    return proc.stdout.strip(), None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # keep container logs to the real hermes gateway, not this shim's access log

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            self._send_json(200, {
                "object": "list",
                "data": [{"id": MODEL_ID, "object": "model", "created": 0, "owned_by": "hermes"}],
            })
            return
        self._send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            self._send_json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid JSON body"})
            return

        messages = body.get("messages") or []
        prompt = last_user_message(messages)
        if not prompt:
            self._send_json(400, {"error": "no user message found in messages[]"})
            return

        session = session_key_for(messages)
        reply, err = run_hermes(prompt, session)
        created = int(time.time())
        completion_id = f"chatcmpl-{uuid.uuid4().hex[:24]}"

        if err is not None:
            if body.get("stream"):
                self._stream_error(completion_id, created, err)
            else:
                self._send_json(502, {"error": err})
            return

        if body.get("stream"):
            self._stream_reply(completion_id, created, reply)
        else:
            self._send_json(200, {
                "id": completion_id,
                "object": "chat.completion",
                "created": created,
                "model": MODEL_ID,
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": reply},
                    "finish_reason": "stop",
                }],
                "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
            })

    def _sse_chunk(self, completion_id, created, delta, finish_reason=None):
        chunk = {
            "id": completion_id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": MODEL_ID,
            "choices": [{"index": 0, "delta": delta, "finish_reason": finish_reason}],
        }
        self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))

    def _start_stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

    def _stream_reply(self, completion_id, created, reply):
        self._start_stream()
        self._sse_chunk(completion_id, created, {"role": "assistant", "content": reply})
        self._sse_chunk(completion_id, created, {}, finish_reason="stop")
        self.wfile.write(b"data: [DONE]\n\n")

    def _stream_error(self, completion_id, created, err):
        self._start_stream()
        self._sse_chunk(completion_id, created, {"role": "assistant", "content": f"[hermes error: {err}]"})
        self._sse_chunk(completion_id, created, {}, finish_reason="stop")
        self.wfile.write(b"data: [DONE]\n\n")


def main():
    port = int(os.environ.get("HERMES_SHIM_PORT", "8642"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
