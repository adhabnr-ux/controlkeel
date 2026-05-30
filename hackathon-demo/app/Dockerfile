# ControlKeel × Gemini governed agent — Cloud Run container
FROM python:3.12-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    PORT=8080

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Cloud Run sends traffic to $PORT. One worker keeps the bootstrapped CK session
# in-process; threads handle demo concurrency. 0.0.0.0 so the platform can reach it.
CMD exec gunicorn --bind "0.0.0.0:${PORT}" --workers 1 --threads 8 --timeout 120 main:app
