FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY relay_server.py .

# The relay runs as an unprivileged user. The stats volume is mounted root-owned at start, so
# the start command hands it to that user first and then drops every privilege for good.
RUN useradd --system --no-create-home --uid 10001 relay

EXPOSE 8765

CMD ["sh", "-c", "if [ -d /data ]; then chown -R relay:relay /data; fi; exec setpriv --reuid=relay --regid=relay --init-groups --no-new-privs python relay_server.py --port 8765"]
