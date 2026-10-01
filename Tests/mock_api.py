from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import sys


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            assert self.path == "/chat/completions"
            assert self.headers.get("Authorization") == "Bearer smoke-key"
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            assert body["model"] == "deepseek-flash"
            assert body["stream"] is True
            thinking = body["thinking"]["type"]
            assert thinking in ("enabled", "disabled")
            if thinking == "enabled":
                assert body["reasoning_effort"] == "high"
                parts = body["messages"][0]["content"]
                assert parts[0] == {"type": "text", "text": "看图"}
                assert parts[1]["image_url"]["url"].startswith("data:image/png;base64,")
            else:
                assert "reasoning_effort" not in body
                assert body["messages"] == [{"role": "user", "content": "你好"}]
        except (AssertionError, KeyError, ValueError) as error:
            payload = json.dumps({"error": {"message": f"Mock rejected request: {error}"}}).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        lines = []
        if thinking == "enabled":
            lines.append('data: {"choices":[{"delta":{"reasoning_content":"想"}}]}\n\n')
        lines += ['data: {"choices":[{"delta":{"content":"好"}}]}\n\n', 'data: [DONE]\n\n']
        payload = "".join(lines).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w", encoding="utf-8") as output:
    output.write(str(server.server_port))
server.serve_forever()
