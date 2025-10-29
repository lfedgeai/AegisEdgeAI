from flask import Flask, request  # <-- NEW: Import request object
import logging

app = Flask(__name__)

# Configure logging to see success messages
gunicorn_logger = logging.getLogger('gunicorn.error')
app.logger.handlers = gunicorn_logger.handlers
app.logger.setLevel(gunicorn_logger.level)

@app.route("/")
def hello_secure():
    """
    This route is only reachable by clients that present a valid
    client certificate signed by our CA.
    """
    
    # --- NEW: Read header and log it ---
    req_id = request.headers.get('X-Request-ID', 'N/A')
    app.logger.info(f"[ReqID: {req_id}] Successful GET / request received from an authorized mTLS client.")
    
    # NEW: Return the ID as well for confirmation
    return f"[ReqID: {req_id}] Success! mTLS connection to CUSTOM PYTHON BACKEND established."
    # -----------------------------------