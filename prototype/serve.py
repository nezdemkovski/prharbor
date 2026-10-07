#!/usr/bin/env python3
"""Static server for the prototype that disables caching, so edits and fresh data.js show up on reload."""
import http.server
import sys
from functools import partial
from pathlib import Path


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


port = int(sys.argv[1]) if len(sys.argv) > 1 else 4173
handler = partial(NoCache, directory=str(Path(__file__).parent))
http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
