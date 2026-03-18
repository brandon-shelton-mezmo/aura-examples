#!/bin/bash
# test-agents.sh — Start MCP servers and test any agent config
#
# Usage:
#   ./test-agents.sh start-servers     # Start MCP servers (run once)
#   ./test-agents.sh stop-servers      # Stop MCP servers
#   ./test-agents.sh run <config>      # Start aura with a config
#   ./test-agents.sh ask "<question>"  # Send a question to the running agent
#   ./test-agents.sh stop              # Stop aura (keeps MCP servers running)
#
# Example full workflow:
#   ./test-agents.sh start-servers
#   ./test-agents.sh run aws-discovery-agent.toml
#   ./test-agents.sh ask "Discover all S3 buckets and store them"
#   ./test-agents.sh stop
#   ./test-agents.sh run aws-incident-response-agent.toml
#   ./test-agents.sh ask "What resources do we have? Check the knowledge base."
#   ./test-agents.sh stop
#   ./test-agents.sh stop-servers

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AURA_BIN="${AURA_BIN:-$HOME/Documents/GitHub/aura/target/release/aura-web-server}"
AURA_PORT=8080
AWS_MCP_PORT=8090
QDRANT_MCP_PORT=8000

# Pull AWS credentials from CLI config if not set
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(aws configure get aws_access_key_id 2>/dev/null)}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(aws configure get aws_secret_access_key 2>/dev/null)}"
export AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
export QDRANT_API_KEY="${QDRANT_API_KEY:-}"

case "${1}" in
  start-servers)
    echo "Starting MCP servers..."

    # Start AWS API MCP server (HTTP mode)
    if lsof -i :$AWS_MCP_PORT >/dev/null 2>&1; then
      echo "  AWS MCP already running on port $AWS_MCP_PORT"
    else
      AWS_API_MCP_TRANSPORT=streamable-http \
      AWS_API_MCP_PORT=$AWS_MCP_PORT \
      AUTH_TYPE=no-auth \
      READ_OPERATIONS_ONLY=true \
      "$HOME/.local/bin/awslabs.aws-api-mcp-server" > /tmp/aws-mcp.log 2>&1 &
      echo "  AWS MCP server starting on port $AWS_MCP_PORT (pid $!)"
      sleep 3
    fi

    # Start Qdrant MCP server (HTTP mode)
    if lsof -i :$QDRANT_MCP_PORT >/dev/null 2>&1; then
      echo "  Qdrant MCP already running on port $QDRANT_MCP_PORT"
    else
      QDRANT_URL=http://localhost:6333 \
      COLLECTION_NAME=aws_resources \
      "$HOME/.local/bin/mcp-server-qdrant" --transport streamable-http > /tmp/qdrant-mcp.log 2>&1 &
      echo "  Qdrant MCP server starting on port $QDRANT_MCP_PORT (pid $!)"
      sleep 3
    fi

    # Verify
    echo ""
    echo "Checking connections:"
    curl -sf http://localhost:$AWS_MCP_PORT/mcp >/dev/null 2>&1 && echo "  ✓ AWS MCP:    http://localhost:$AWS_MCP_PORT/mcp" || echo "  ✗ AWS MCP:    NOT RESPONDING (check /tmp/aws-mcp.log)"
    curl -sf http://localhost:$QDRANT_MCP_PORT/mcp >/dev/null 2>&1 && echo "  ✓ Qdrant MCP: http://localhost:$QDRANT_MCP_PORT/mcp" || echo "  ✗ Qdrant MCP: NOT RESPONDING (check /tmp/qdrant-mcp.log)"
    curl -sf http://localhost:6333/ >/dev/null 2>&1 && echo "  ✓ Qdrant DB:  http://localhost:6333" || echo "  ✗ Qdrant DB:  NOT RUNNING (start with: docker run -d -p 6333:6333 qdrant/qdrant)"
    echo ""
    echo "Ready. Run: ./test-agents.sh run <config-file>"
    ;;

  stop-servers)
    echo "Stopping MCP servers..."
    pkill -f "awslabs.aws-api-mcp-server" 2>/dev/null && echo "  Stopped AWS MCP" || echo "  AWS MCP not running"
    pkill -f "mcp-server-qdrant" 2>/dev/null && echo "  Stopped Qdrant MCP" || echo "  Qdrant MCP not running"
    ;;

  run)
    CONFIG="${2}"
    if [ -z "$CONFIG" ]; then
      echo "Usage: ./test-agents.sh run <config-file>"
      echo ""
      echo "Available configs:"
      ls "$SCRIPT_DIR"/*.toml 2>/dev/null | while read f; do echo "  $(basename "$f")"; done
      echo ""
      echo "Also available:"
      ls "$SCRIPT_DIR/../../rag/aws-knowledge-base/"*.toml 2>/dev/null | while read f; do echo "  $(basename "$f") (in rag/aws-knowledge-base/)"; done
      exit 1
    fi

    # Find the config file
    if [ -f "$SCRIPT_DIR/$CONFIG" ]; then
      CONFIG_PATH="$SCRIPT_DIR/$CONFIG"
    elif [ -f "$SCRIPT_DIR/../../rag/aws-knowledge-base/$CONFIG" ]; then
      CONFIG_PATH="$SCRIPT_DIR/../../rag/aws-knowledge-base/$CONFIG"
    elif [ -f "$CONFIG" ]; then
      CONFIG_PATH="$CONFIG"
    else
      echo "Config not found: $CONFIG"
      exit 1
    fi

    # Stop existing aura
    pkill -f "aura-web-server" 2>/dev/null
    sleep 1

    echo "Starting aura with: $(basename "$CONFIG_PATH")"
    CONFIG_PATH="$CONFIG_PATH" "$AURA_BIN" > /tmp/aura-agent.log 2>&1 &
    sleep 3

    if curl -sf http://localhost:$AURA_PORT/ >/dev/null 2>&1; then
      echo "  ✓ Aura running on http://localhost:$AURA_PORT"
      echo ""
      echo "Send questions with: ./test-agents.sh ask \"your question\""
    else
      echo "  ✗ Aura failed to start. Check /tmp/aura-agent.log"
      tail -5 /tmp/aura-agent.log
    fi
    ;;

  ask)
    QUESTION="${2}"
    if [ -z "$QUESTION" ]; then
      echo "Usage: ./test-agents.sh ask \"your question\""
      exit 1
    fi

    echo "Asking: $QUESTION"
    echo "---"

    RESPONSE=$(curl -s http://localhost:$AURA_PORT/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d "{\"messages\":[{\"role\":\"user\",\"content\":$(echo "$QUESTION" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')}]}" 2>&1)

    echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'])
    tokens = d.get('usage', {})
    print(f\"\\n--- Tokens: {tokens.get('total_tokens', '?')} (prompt: {tokens.get('prompt_tokens', '?')}, completion: {tokens.get('completion_tokens', '?')}) ---\")
except Exception as e:
    print(f'Error parsing response: {e}')
    print(sys.stdin.read() if hasattr(sys.stdin, 'read') else 'no data')
" 2>&1
    ;;

  stop)
    pkill -f "aura-web-server" 2>/dev/null && echo "Aura stopped" || echo "Aura not running"
    ;;

  status)
    echo "Service status:"
    curl -sf http://localhost:$AWS_MCP_PORT/mcp >/dev/null 2>&1 && echo "  ✓ AWS MCP:    running" || echo "  ✗ AWS MCP:    stopped"
    curl -sf http://localhost:$QDRANT_MCP_PORT/mcp >/dev/null 2>&1 && echo "  ✓ Qdrant MCP: running" || echo "  ✗ Qdrant MCP: stopped"
    curl -sf http://localhost:6333/ >/dev/null 2>&1 && echo "  ✓ Qdrant DB:  running" || echo "  ✗ Qdrant DB:  stopped"
    curl -sf http://localhost:$AURA_PORT/ >/dev/null 2>&1 && echo "  ✓ Aura:       running" || echo "  ✗ Aura:       stopped"
    POINTS=$(curl -s http://localhost:6333/collections/aws_resources 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['points_count'])" 2>/dev/null || echo "?")
    echo "  KB points:    $POINTS documents in aws_resources"
    ;;

  *)
    echo "Usage: ./test-agents.sh <command>"
    echo ""
    echo "Commands:"
    echo "  start-servers    Start AWS MCP + Qdrant MCP servers (run once)"
    echo "  stop-servers     Stop MCP servers"
    echo "  run <config>     Start aura with a specific agent config"
    echo "  ask \"question\"   Send a question to the running agent"
    echo "  stop             Stop aura (keeps MCP servers running)"
    echo "  status           Check what's running"
    ;;
esac
