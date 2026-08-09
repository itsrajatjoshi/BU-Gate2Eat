import http.server
import socketserver
import os

PORT = 8080

if __name__ == '__main__':
    web_dir = os.path.join(os.path.dirname(__file__), 'build', 'web')
    os.chdir(web_dir)
    Handler = http.server.SimpleHTTPRequestHandler
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"Serving HTTP on 0.0.0.0 port {PORT} (http://localhost:{PORT} and http://127.0.0.1:{PORT})...")
        httpd.serve_forever()

