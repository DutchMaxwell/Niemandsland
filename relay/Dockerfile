FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY relay_server.py .

EXPOSE 8765

CMD ["python", "relay_server.py", "--port", "8765"]
