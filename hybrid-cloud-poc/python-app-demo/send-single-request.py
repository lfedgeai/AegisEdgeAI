#!/usr/bin/env python3
"""
Send a single HTTP request via mTLS using SPIRE SVID.
This is used for demos where we want to show a single, decodable request.
"""

import os
import sys
import socket
import ssl
import time

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from spiffe.workloadapi import default_workload_api_client
    HAS_SPIFFE = True
except ImportError:
    HAS_SPIFFE = False

def get_tls_context():
    """Get TLS context with SPIRE SVID."""
    socket_path = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    
    if not HAS_SPIFFE:
        print("ERROR: spiffe library not available")
        sys.exit(1)
    
    if not os.path.exists(socket_path):
        print(f"ERROR: SPIRE agent socket not found: {socket_path}")
        sys.exit(1)
    
    # Create workload API client
    client = default_workload_api_client(socket_path)
    source = client.fetch_x509_source()
    
    # Get SVID
    svid = source.get_x509_svid()
    if not svid:
        print("ERROR: Failed to get SVID from SPIRE agent")
        sys.exit(1)
    
    # Get trust bundle
    bundle = source.get_bundle()
    if not bundle:
        print("ERROR: Failed to get trust bundle from SPIRE agent")
        sys.exit(1)
    
    # Create SSL context
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_REQUIRED
    
    # Load client certificate and key
    context.load_cert_chain(
        certfile=svid.cert_file,
        keyfile=svid.key_file
    )
    
    # Load CA certificate from bundle
    bundle_file = bundle.cert_file
    context.load_verify_locations(cafile=bundle_file)
    
    return context, source

def send_single_request(server_host, server_port):
    """Send a single HTTP request and display the response."""
    print(f"Connecting to {server_host}:{server_port}...")
    
    # Get TLS context
    context, source = get_tls_context()
    
    # Create socket and wrap with TLS
    client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tls_socket = context.wrap_socket(client_socket, server_hostname=server_host)
    
    try:
        tls_socket.connect((server_host, server_port))
        print("✓ Connected to server")
        
        # Send single HTTP request
        http_request = (
            f"GET /hello HTTP/1.1\r\n"
            f"Host: {server_host}:{server_port}\r\n"
            f"User-Agent: mTLS-Client-Demo/1.0\r\n"
            f"X-Message: HELLO #1\r\n"
            f"Connection: close\r\n"
            f"\r\n"
        )
        
        print(f"📤 Sending HTTP request:")
        print(http_request.replace('\r\n', '\n').replace('\r', '')[:200])
        
        tls_socket.sendall(http_request.encode('utf-8'))
        
        # Receive response
        print("📥 Waiting for response...")
        response_data = b""
        while True:
            chunk = tls_socket.recv(4096)
            if not chunk:
                break
            response_data += chunk
            # Check if we've received the full response (HTTP headers + body)
            if b'\r\n\r\n' in response_data:
                # Check if Content-Length is specified
                headers = response_data.split(b'\r\n\r\n')[0]
                if b'Content-Length:' in headers:
                    # Parse Content-Length and read body
                    for line in headers.split(b'\r\n'):
                        if line.startswith(b'Content-Length:'):
                            content_length = int(line.split(b':')[1].strip())
                            if len(response_data) >= len(headers) + 4 + content_length:
                                break
                else:
                    # No Content-Length, assume response is complete
                    break
        
        response = response_data.decode('utf-8', errors='ignore')
        print(f"✓ Received response:")
        print(response[:500])  # Show first 500 chars
        
        # Extract status code
        if 'HTTP/1.1' in response or 'HTTP/1.0' in response:
            status_line = response.split('\n')[0]
            print(f"\nStatus: {status_line.strip()}")
        
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        tls_socket.close()
        if source:
            source.close()
    
    print("\n✓ Single request completed successfully")

if __name__ == '__main__':
    server_host = os.environ.get('SERVER_HOST', '10.1.0.10')
    server_port = int(os.environ.get('SERVER_PORT', '8080'))
    
    send_single_request(server_host, server_port)

