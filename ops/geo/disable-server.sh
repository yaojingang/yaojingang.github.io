#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"
task_config=/etc/laoyao-geo
task_lock="$task_root/.git/laoyao-deploy.lock"
[[ "$(git symbolic-ref --short HEAD)" == main ]]
git diff --quiet
git diff --cached --quiet
[[ -f "$task_config/nginx.previous.conf" ]]
mkdir "$task_lock"
trap 'rmdir "$task_lock" 2>/dev/null || true' EXIT
docker run --rm --network none -v "$task_config/nginx.previous.conf:/etc/nginx/conf.d/default.conf:ro" nginx:1.31.1-alpine nginx -t
docker compose -f docker-compose.laoyao.yml -f ops/geo/docker-compose.yml stop geo-api
cp "$task_config/nginx.previous.conf" docker/nginx.conf
if [[ -f "$task_config/enabled" ]]; then
  mv "$task_config/enabled" "$task_config/disabled"
fi
mkdir -p .git/laoyao-deploy
touch .git/laoyao-deploy/reconfigure
rmdir "$task_lock"
trap - EXIT
unset SSH_ORIGINAL_COMMAND
printf 'GEO 实时内测已关闭，正在恢复博客服务。\n'
exec bash ops/laoyao/deploy.sh
