#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ruby "$task_root/backend/geo/configure.rb"
printf '\n完成后可以关闭此窗口。\n'
read -r -p "按回车结束。"
