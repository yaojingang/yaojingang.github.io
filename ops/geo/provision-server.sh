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
mkdir "$task_lock"
mkdir -p "$task_config"
chmod 700 "$task_config"
cleanup() {
  rm -f "$task_config/pending.json" "$task_config/credentials.next.json" "$task_config/nginx.candidate.conf"
  rmdir "$task_lock" 2>/dev/null || true
}
trap cleanup EXIT
head -c 16385 > "$task_config/pending.json"
task_commit=$(git rev-parse HEAD)
docker run --rm --network none -v "$task_root:/repo:ro" -v "$task_config:/config" ruby:3.3-alpine \
  ruby /repo/ops/geo/provision-payload.rb /config/pending.json /config /repo/docker/nginx.conf /repo/ops/geo/nginx-location.conf "$task_commit"
docker run --rm --network none -v "$task_config/nginx.candidate.conf:/etc/nginx/conf.d/default.conf:ro" nginx:1.31.1-alpine nginx -t
docker compose -f docker-compose.laoyao.yml -f ops/geo/docker-compose.yml config --quiet
[[ -f "$task_config/nginx.previous.conf" ]] || cp -p docker/nginx.conf "$task_config/nginx.previous.conf"
if [[ -f "$task_config/credentials.json" ]]; then
  cp -p "$task_config/credentials.json" "$task_config/credentials.previous.json"
fi
mv "$task_config/credentials.next.json" "$task_config/credentials.json"
cp "$task_config/nginx.candidate.conf" docker/nginx.conf
touch "$task_config/enabled"
mkdir -p .git/laoyao-deploy
touch .git/laoyao-deploy/reconfigure
printf 'GEO 密钥已安装，正在构建内测服务。\n'
cleanup
trap - EXIT
unset SSH_ORIGINAL_COMMAND
exec bash ops/laoyao/deploy.sh
