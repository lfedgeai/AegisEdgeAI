from flask import Flask, request
import logging

app = Flask(__name__)

# Configure logging
gunicorn_logger = logging.getLogger('gunicorn.error')
app.logger.handlers = gunicorn_logger.handlers
app.logger.setLevel(gunicorn_logger.level)

@app.route("/", methods=['GET', 'POST']) # Accept POST requests
def hello_secure():
    """
    Handles mTLS requests. If it's a POST, it looks for a request_id.
    """
    request_id = "N/A"
    if request.is_json:
        try:
            data = request.get_json()
            request_id = data.get('request_id', 'N/A')
        except Exception:
            pass # Ignore errors if JSON is bad
    
    # This is the new log your mentor wants to see
    app.logger.info(f"BACKEND: Received request with ID: {request_id}")
    
    return f"BACKEND: Success! mTLS connection established. Processed ID: {request_id}", 200