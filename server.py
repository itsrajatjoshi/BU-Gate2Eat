import http.server
import socketserver
import os

PORT = 8080

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress noisy request logging
        pass

class RobustServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

if __name__ == '__main__':
    web_dir = os.path.join(os.path.dirname(__file__), 'build', 'web')
    os.chdir(web_dir)
    with RobustServer(("", PORT), QuietHandler) as httpd:
        print(f"Serving HTTP on 0.0.0.0 port {PORT} (http://localhost:{PORT})...")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass

