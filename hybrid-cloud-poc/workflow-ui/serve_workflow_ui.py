#!/usr/bin/env python3

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Simple HTTP server to serve the workflow visualization UI.
Access at: http://10.1.0.11:8080/workflow_visualization.html
"""

import http.server
import socketserver
import os
import sys
from pathlib import Path

PORT = 8080
HTML_FILE = '/tmp/workflow_visualization.html'

class WorkflowUIHandler(http.server.SimpleHTTPRequestHandler):
    """Custom handler to serve the workflow visualization."""

    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/' or self.path == '/workflow_visualization.html':
            # Serve the workflow visualization
            if os.path.exists(HTML_FILE):
                self.send_response(200)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                with open(HTML_FILE, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                error_msg = f"""
                <html>
                <head><title>404 - Not Found</title></head>
                <body>
                    <h1>404 - Workflow Visualization Not Found</h1>
                    <p>The workflow visualization file does not exist at: {HTML_FILE}</p>
                    <p>Please run the test suite first to generate it:</p>
                    <pre>./test_phase3_complete.sh --no-pause</pre>
                    <p>Or generate it manually:</p>
                    <pre>python3 generate_workflow_ui.py</pre>
                </body>
                </html>
                """
                self.wfile.write(error_msg.encode())
        elif self.path == '/health':
            # Health check endpoint
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b'404 - Not Found')

    def log_message(self, format, *args):
        """Override to suppress default logging."""
        # Only log errors
        if '404' in format % args or '500' in format % args:
            sys.stderr.write("%s - - [%s] %s\n" %
                           (self.address_string(),
                            self.log_date_time_string(),
                            format % args))


def main():
    """Main function to start the HTTP server."""
    if not os.path.exists(HTML_FILE):
        print(f"Error: Workflow visualization file not found: {HTML_FILE}")
        print("Please run the test suite first to generate it:")
        print("  ./test_phase3_complete.sh --no-pause")
        print("Or generate it manually:")
        print("  python3 generate_workflow_ui.py")
        sys.exit(1)

    Handler = WorkflowUIHandler

    try:
        with socketserver.TCPServer(("", PORT), Handler) as httpd:
            print("=" * 70)
            print("Workflow Visualization UI Server")
            print("=" * 70)
            print(f"Server running at: http://0.0.0.0:{PORT}/workflow_visualization.html")
            print(f"Local access:      http://localhost:{PORT}/workflow_visualization.html")
            print(f"Network access:    http://10.1.0.11:{PORT}/workflow_visualization.html")
            print("=" * 70)
            print("Press Ctrl+C to stop the server")
            print("=" * 70)
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n\nServer stopped.")
        sys.exit(0)
    except OSError as e:
        if e.errno == 98:  # Address already in use
            print(f"Error: Port {PORT} is already in use.")
            print("Please stop the existing server or use a different port.")
        else:
            print(f"Error starting server: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
