#!/usr/bin/env python3
"""
Thin OpenAI-compatible HTTP shim in front of the Hermes CLI (issue: Open WebUI <-> Hermes).

hermes-agent has no HTTP agent API (its only HTTP server is the secrets-management
dashboard, deliberately not exposed). Open WebUI is already wired to try
http://hermes:8642/v1 as a second backend (see open-webui.yml OPENAI_API_BASE_URLS)
but nothing has ever listened there. This process is that listener: it shells out
to the real `hermes -z ... --cli --continue <session>` for every request and wraps
stdout in an OpenAI chat.completion(.chunk) envelope.

Session mapping: the OpenAI chat-completions protocol carries no conversation id,
but Open WebUI resends the full message history every turn. We derive a stable
Hermes --continue session key from a hash of the first user message in that
history, so turns within one Open WebUI chat share one Hermes session (memory,
persona) while distinct chats get distinct sessions. This is a per-chat mapping,
not a cross-surface (Telegram <-> Open WebUI) one -- that unification is #31,
deliberately out of scope here.

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


def session_key_for(messages):
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
