# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory
WORKDIR /app

# Copy the requirements file
COPY requirements.txt .

# Install the dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY app.py .

# Define the command to run Gunicorn
# This is the most important part.
# Make sure the paths match your CSI volumeMounts.
# ... (all your FROM, COPY, RUN lines) ...

# CORRECTED Gunicorn command:
# ... (all your FROM, COPY, RUN lines) ...

# CORRECTED Gunicorn command (using '2' for CERT_REQUIRED):
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8443", \
     "--certfile", "/var/run/secrets/mtls/tls.crt", \
     "--keyfile", "/var/run/secrets/mtls/tls.key", \
     "--ca-certs", "/var/run/secrets/mtls/ca.crt", \
     "--cert-reqs", "2", \
     "--log-level", "debug", \
     "app:app"]