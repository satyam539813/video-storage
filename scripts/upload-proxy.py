#!/usr/bin/env python3
"""Local upload proxy: browser drag-and-drop -> GitHub Release assets.

GitHub's release-asset upload host (uploads.github.com) does not send CORS
headers, so browsers cannot upload release assets directly from a web page.
This tiny local server accepts uploads from the web UI (uploader.html) and
forwards them using the already-authenticated `gh` CLI, so no token ever
passes through the browser.

Usage:
    python3 scripts/upload-proxy.py [port]      # default port 8787

Endpoints:
    GET  /health                                    -> {"ok": true}
    POST /upload-release?repo=OWNER/REPO&tag=T&name=N
        Body: raw file bytes
        Result: {"ok": true, "name": ..., "url": ...}

Release assets allow up to 2 GiB per file with no total size or bandwidth cap.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, quote

MAX_BYTES = 2 * 1024 * 1024 * 1024 - 1  # GitHub release asset limit: 2 GiB


def gh(args):
    return subprocess.run(["gh"] + args, capture_output=True, text=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        # Chrome's Private Network Access preflight (https page -> localhost)
        if self.headers.get("Access-Control-Request-Private-Network"):
            self.send_header("Access-Control-Allow-Private-Network", "true")

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if urlparse(self.path).path == "/health":
            self._json({"ok": True, "service": "upload-proxy"})
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/upload-release":
            self._json({"error": "unknown endpoint"}, 404)
            return
        qs = parse_qs(parsed.query)
        repo = (qs.get("repo") or [None])[0]
        tag = (qs.get("tag") or [None])[0]
        name = (qs.get("name") or [None])[0]
        if not (repo and tag and name):
            self._json({"error": "repo, tag and name are required"}, 400)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0:
            self._json({"error": "empty request body"}, 400)
            return
        if length > MAX_BYTES:
            self._json({"error": "file exceeds the 2 GiB GitHub release asset limit"}, 413)
            return

        ok, result = self._upload(repo, tag, name, length)
        if ok:
            self._json(result)
        else:
            self._json({"ok": False, "error": result}, 500)

    def _get_release(self, repo, tag):
        """Returns (release_dict | None, error_string | None)."""
        r = gh(["api", f"repos/{repo}/releases/tags/{quote(tag, safe='')}"])
        if r.returncode == 0:
            try:
                return json.loads(r.stdout), None
            except ValueError:
                return None, "unexpected response from GitHub API"
        if "404" in (r.stderr or ""):
            c = gh(["release", "create", tag, "--repo", repo,
                    "--title", tag, "--notes", "Uploaded via web uploader"])
            if c.returncode != 0:
                return None, (c.stderr or "could not create release").strip()
            return None, None
        return None, (r.stderr or "could not read release").strip()

    def _upload(self, repo, tag, name, length):
        release, err = self._get_release(repo, tag)
        if err:
            return False, err
        asset_names = [a["name"] for a in (release or {}).get("assets", [])]

        # unique asset name (release asset names must be unique)
        stem, ext = os.path.splitext(name)
        final = name
        n = 1
        while final in asset_names:
            n += 1
            final = f"{stem}-{n}{ext}"

        # stream the body to a temp file named after the final asset
        tmpdir = tempfile.mkdtemp(prefix="ghupload-")
        try:
            target = os.path.join(tmpdir, final)
            remaining = length
            with open(target, "wb") as f:
                while remaining > 0:
                    chunk = self.rfile.read(min(1 << 20, remaining))
                    if not chunk:
                        break
                    f.write(chunk)
                    remaining -= len(chunk)
            if remaining > 0:
                return False, f"incomplete upload: {remaining} bytes missing"

            u = gh(["release", "upload", tag, target, "--repo", repo])
            if u.returncode != 0:
                return False, (u.stderr or "upload failed").strip()

            v = gh(["api", f"repos/{repo}/releases/tags/{quote(tag, safe='')}"])
            if v.returncode == 0:
                for a in json.loads(v.stdout).get("assets", []):
                    if a["name"] == final:
                        return True, {"ok": True, "name": final,
                                      "size": a.get("size"),
                                      "url": a.get("browser_download_url")}
            return True, {"ok": True, "name": final, "url": None}
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def log_message(self, fmt, *args):
        print("proxy:", fmt % args)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Upload proxy listening on http://127.0.0.1:{port} (Ctrl+C to stop)")
    print("Large drag-and-drop uploads from uploader.html will now become")
    print("GitHub release assets (up to 2 GiB per file).")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
