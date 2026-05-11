#!/usr/bin/env python3
# Tiny HTTP -> HTTPS 301 redirector on :80.
# Some browsers (Tesla's older Chromium, clients without HSTS cache) try
# http://<host> first. Without anything on :80 the kernel sends TCP RST and
# the browser shows ERR_CONNECTION_REFUSED. We answer with a 301 to the
# same path under https://, then the browser does the right thing.
from http.server import BaseHTTPRequestHandler, HTTPServer

class Redirect(BaseHTTPRequestHandler):
    def do_GET(self):  self._redirect()
    def do_HEAD(self): self._redirect()
    def do_POST(self): self._redirect()
    def _redirect(self):
        host = (self.headers.get('Host') or '').split(':')[0]
        target = f"https://{host}{self.path}"
        self.send_response(301)
        self.send_header('Location', target)
        self.send_header('Content-Length', '0')
        self.end_headers()
    def log_message(self, *_): pass

if __name__ == '__main__':
    HTTPServer(('', 80), Redirect).serve_forever()
