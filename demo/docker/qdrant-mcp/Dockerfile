FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt boto3>=1.35.0 mcp-proxy

COPY server.py .

ENV QDRANT_URL=http://localhost:6333

EXPOSE 8000

# mcp-proxy spawns python server.py as a subprocess — must explicitly pass env vars.
# AWS_CONTAINER_CREDENTIALS_RELATIVE_URI is set by ECS and needed for boto3 task role auth.
# We build the mcp-proxy args dynamically to conditionally include ECS credential URI.
CMD ["/bin/sh", "-c", "\
echo \"Testing Qdrant at $QDRANT_URL\" && \
for i in 1 2 3 4 5 6 7 8 9 10; do \
  curl -sf $QDRANT_URL/ && echo ' Qdrant OK' && break || echo \" Qdrant not ready, attempt $i/10...\"; \
  sleep 5; \
done && \
echo \"Starting mcp-proxy with QDRANT_URL=$QDRANT_URL\" && \
EXTRA_ARGS=\"\" && \
if [ -n \"$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI\" ]; then \
  EXTRA_ARGS=\"-e AWS_CONTAINER_CREDENTIALS_RELATIVE_URI $AWS_CONTAINER_CREDENTIALS_RELATIVE_URI\"; \
fi && \
exec mcp-proxy --transport streamablehttp --host 0.0.0.0 --port 8000 \
  -e QDRANT_URL $QDRANT_URL \
  -e AWS_REGION ${AWS_REGION:-us-east-1} \
  -e AWS_DEFAULT_REGION ${AWS_REGION:-us-east-1} \
  $EXTRA_ARGS \
  -- python /app/server.py"]
