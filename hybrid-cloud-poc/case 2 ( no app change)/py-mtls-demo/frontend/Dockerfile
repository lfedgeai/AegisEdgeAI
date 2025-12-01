# This is frontend/Dockerfile
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .

# requirements.txt is empty, but this step is fine
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

# THIS IS THE CORRECT COMMAND for the client
CMD ["python", "app.py"]