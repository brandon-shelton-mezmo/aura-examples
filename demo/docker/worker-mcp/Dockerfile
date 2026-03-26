FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt mcp-proxy

COPY server.py .

ENV AURA_WORKER_URL=http://localhost:3030
ENV WORKER_TIMEOUT=300
ENV MAX_PARALLEL=10

EXPOSE 8095

CMD ["/bin/sh", "-c", "exec mcp-proxy --transport streamablehttp --host 0.0.0.0 --port 8095 -e AURA_WORKER_URL $AURA_WORKER_URL -e WORKER_TIMEOUT $WORKER_TIMEOUT -e MAX_PARALLEL $MAX_PARALLEL -- python /app/server.py"]
