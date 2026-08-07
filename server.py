import http.server
import socket
import os

class DualStackHTTPServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6

    def server_bind(self):
        # Dual-stack option (IPv4 and IPv6)
        try:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        except Exception:
            pass
        super().server_bind()

if __name__ == '__main__':
    web_dir = os.path.join(os.path.dirname(__file__), 'build', 'web')
    os.chdir(web_dir)
    handler = http.server.SimpleHTTPRequestHandler
    # Bind to :: (all interfaces including IPv6 localhost ::1 and IPv4 127.0.0.1)
    with DualStackHTTPServer(('::', 8080), handler) as httpd:
        print("Serving HTTP on :: port 8080 (http://localhost:8080 and http://127.0.0.1:8080)...")
        httpd.serve_forever()
