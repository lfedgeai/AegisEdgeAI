import http.client
import ssl
import logging
import os
import json # Import json
from flask import Flask, Response, request # Import request

# --- App Setup ---
app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

# --- mTLS Client Setup ---
CERT_PATH = "/etc/tls/tls.crt"
KEY_PATH = "/etc/tls/tls.key"
CA_PATH = "/etc/tls/ca.crt"
BACKEND_HOST = "backend-svc"
BACKEND_PORT = 8443

# Global variables to hold our single, persistent connection
ssl_context = None
backend_connection = None

def create_mtls_connection():
    """
    Creates a new SSL context and a new HTTPS connection.
    This function is called on startup and after a failure.
    """
    global ssl_context, backend_connection
    try:
        log.info("Creating new mTLS SSLContext...")
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=CA_PATH)
        context.load_cert_chain(certfile=CERT_PATH, keyfile=KEY_PATH)
        
        ssl_context = context
        
        log.info("Establishing new persistent HTTPSConnection...")
        backend_connection = http.client.HTTPSConnection(
            host=BACKEND_HOST,
            port=BACKEND_PORT,
            context=ssl_context,
            timeout=1.0  # 1-second timeout
        )
        # Make one request to "open" the connection
        # Make one POST request to "open" the connection and test JSON handling
        init_data = json.dumps({"request_id": "INIT"})
        headers = {'Content-Type': 'application/json'}
        backend_connection.request("POST", "/", body=init_data, headers=headers)
        response = backend_connection.getresponse()
        log.info(f"New mTLS connection established. Initial POST status: {response.status}")
    # Read the response body to allow reusing the connection
        response.read()
        
    except Exception as e:
        log.error(f"Failed to create mTLS connection: {e}")
        backend_connection = None

# Create the very first connection on startup
create_mtls_connection()

# --- Server Endpoint for curl-pod ---
@app.route("/", methods=['GET', 'POST']) # Accept POST requests
def http_handler():
    """
    Handles HTTP requests from the curl-pod.
    Tries to use the single, persistent mTLS connection.
    """
    global backend_connection
    
    # Get the request_id from the curl-pod's JSON
    request_id = "N/A"
    if request.is_json:
        try:
            data = request.get_json()
            request_id = data.get('id', 'N/A')
        except Exception:
            pass # Ignore errors
            
    log.info(f"FRONTEND: HTTP request received from curl-pod with ID: {request_id}")
    
    if backend_connection is None:
        log.warning(f"!!! DROPPED REQUEST ID: {request_id} !!! mTLS connection is 'None'. Re-creating...")
        create_mtls_connection() # Try to fix it for next time
        return "ERROR: mTLS connection is down (None).", 503

    try:
        # Prepare JSON data to forward to backend
        forward_data = json.dumps({"request_id": request_id})
        headers = {'Content-Type': 'application/json'}
        
        # 1. Try to use the existing, long-lived connection
        backend_connection.request("POST", "/", body=forward_data, headers=headers)
        response = backend_connection.getresponse()
        
        if response.status == 200:
            log.info(f"FRONTEND: mTLS connection is UP. Forwarded ID: {request_id}")
            return "SUCCESS: Backend connection is active.", 200
        else:
            log.warning(f"mTLS connection is UP, but backend returned {response.status}")
            return "ERROR: Backend returned an error.", 500

    except (ssl.SSLError, BrokenPipeError, http.client.CannotSendRequest) as e:
        # 2. THIS IS THE FAILURE!
        log.error(f"!!! DROPPED REQUEST ID: {request_id} !!! mTLS connection failed: {e}")
        log.info("RE-ESTABLISHING mTLS CONNECTION...")
        
        # 3. THIS IS THE RECOVERY!
        create_mtls_connection() 
        
        return "ERROR: mTLS connection reset, dropping request.", 503
        
    except Exception as e:
        # 4. Other unexpected errors
        log.error(f"!!! DROPPED REQUEST ID: {request_id} !!! Unknown error: {e}")
        return "ERROR: Unknown error, dropping request.", 500

# --- Main execution ---
if __name__ == "__main__":
    log.info("Flask app initialized for Gunicorn.")