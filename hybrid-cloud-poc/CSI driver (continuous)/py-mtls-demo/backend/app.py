from flask import Flask

# Create the Flask application object
app = Flask(__name__)

@app.route("/")
def hello_secure():
    """
    This route is only reachable by clients that present a valid
    client certificate signed by our CA.
    """
    
    # This log will now appear in the Gunicorn logs on a successful request.
    # This helps you distinguish a successful auth from a failed one.
    app.logger.info("Successful GET / request received from an authorized mTLS client.")
    
    # Return the success message
    return "Success! mTLS connection to CUSTOM PYTHON BACKEND established."

#
# That's it!
#
# DO NOT add the 'if __name__ == "__main__":' block.
# Gunicorn will find and run the 'app' object automatically
# (using the "app:app" argument in the Dockerfile CMD).
#
# The Gunicorn CMD in the Dockerfile handles all the SSL/TLS and port configuration.
#