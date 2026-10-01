#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
test_binary="$(mktemp -t easyask-smoke)"
port_file="$(mktemp -t easyask-port)"
python3 Tests/mock_api.py "${port_file}" &
server_pid=$!
trap 'kill "${server_pid}" 2>/dev/null || true; rm -f "${test_binary}" "${port_file}"' EXIT
for attempt in {1..50}; do
  if [[ -s "${port_file}" ]]; then break; fi
  sleep 0.1
done
if [[ ! -s "${port_file}" ]]; then echo "Mock API failed to start" >&2; exit 1; fi
export EASYASK_TEST_URL="http://127.0.0.1:$(<"${port_file}")/chat/completions"
swiftc -parse-as-library \
  Sources/EasyAsk/DeepSeekClient.swift \
  Sources/EasyAsk/ChatStore.swift \
  Sources/EasyAsk/KeychainStore.swift \
  Sources/EasyAsk/MarkdownBlocks.swift \
  Tests/Smoke.swift \
  -o "${test_binary}"
"${test_binary}"
