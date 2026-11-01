#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
printf '启动后请打开 http://127.0.0.1:4010/geo/\n'
exec ruby "$task_root/backend/geo/server.rb"
