#!/usr/bin/env bash
# Start one copy of the durable agent, with its whole log captured to a file.
#
#   ./local/run-agent.sh A    ports 8000 / 3500 / 50001 / 9091
#   ./local/run-agent.sh B    ports 8001 / 3501 / 50002 / 9092
#
# Both copies deliberately share the app id bank-agent-creditor. That is what
# makes them two replicas of one app, so Dapr placement shares the workflows
# between them. Copy A is the one the web page talks to. Kill copy B.
set -uo pipefail

copy="${1:-}"
case "$copy" in
  A|a) copy=A; app=8000; http=3500; grpc=50001; metrics=9091 ;;
  B|b) copy=B; app=8001; http=3501; grpc=50002; metrics=9092 ;;
  *) echo "usage: $0 A|B" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/logs"
log="$root/logs/agent-$copy-$(date +%Y%m%d-%H%M%S).log"

echo "copy $copy   app:$app  dapr-http:$http  dapr-grpc:$grpc  metrics:$metrics"
echo "log  -> $log"
echo

cd "$root/services/agent-langgraph"
STUB_LLM=true \
PYTHONUNBUFFERED=1 \
MCP_DIRECT_URL=http://localhost:9000/mcp/ \
  dapr run --app-id bank-agent-creditor --app-port "$app" -H "$http" -G "$grpc" -M "$metrics" \
  -- uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port "$app" 2>&1 | tee "$log"
