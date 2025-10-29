FROM python:3.10-slim
WORKDIR /app

# Install dependencies (now includes flask/gunicorn)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the app code
COPY app.py .

# Run Gunicorn to serve the 'app' object from app.py
# This will listen on port 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--log-level", "info", "app:app"]