FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir mcp-proxy awslabs.aws-api-mcp-server

ENV READ_OPERATIONS_ONLY=true
ENV AWS_REGION=us-east-1

EXPOSE 8091

HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=45s \
  CMD curl -sf -X POST http://localhost:8091/mcp \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":0,"method":"ping"}' || exit 1

CMD ["mcp-proxy", "--transport", "streamablehttp", "--host", "0.0.0.0", "--port", "8091", \
     "-e", "READ_OPERATIONS_ONLY", "true", \
     "--", "awslabs.aws-api-mcp-server"]
