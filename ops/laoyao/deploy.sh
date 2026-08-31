#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

EXPECTED_REMOTE="git@github.com:yaojingang/yaojingang.github.io.git"
BRANCH="main"
COMPOSE_FILE="docker-compose.laoyao.yml"
GITHUB_SSH_WRAPPER="$SCRIPT_DIR/git-ssh.sh"
LOCAL_HEALTH_URL="http://127.0.0.1:10001/"
PUBLIC_HEALTH_URL="https://www.laoyao.cn/"
FETCH_ATTEMPTS=3

LOCK_DIR=""
ROLLBACK_COMMIT=""
STATE_DIR=""
DEPLOYED_COMMIT_FILE=""

log() {
  printf '[laoyao-deploy] %s\n' "$*"
}

die() {
  printf '[laoyao-deploy] ERROR: %s\n' "$*" >&2
  if [[ -n "$ROLLBACK_COMMIT" ]]; then
    printf '[laoyao-deploy] rollback commit: %s\n' "$ROLLBACK_COMMIT" >&2
  fi
  exit 1
}

cleanup() {
  if [[ -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

on_error() {
  local status=$?
  trap - ERR
  printf '[laoyao-deploy] ERROR: command failed with status %s\n' "$status" >&2
  if [[ -n "$ROLLBACK_COMMIT" ]]; then
    printf '[laoyao-deploy] rollback commit: %s\n' "$ROLLBACK_COMMIT" >&2
  fi
  exit "$status"
}

trap cleanup EXIT
trap on_error ERR

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command missing: $1"
}

check_worktree() {
  local line status path

  git diff --quiet || die "tracked working-tree changes detected"
  git diff --cached --quiet || die "staged changes detected"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    status=${line:0:2}
    path=${line:3}

    if [[ "$status" == "??" ]]; then
      case "$path" in
        DockerfileProd|_config.laoyao.yml|docker-compose.laoyao.yml|docker/*)
          continue
          ;;
      esac
    fi

    die "unexpected repository state: $line"
  done < <(git status --porcelain --untracked-files=all)
}

fetch_main() {
  local attempt delay

  for ((attempt = 1; attempt <= FETCH_ATTEMPTS; attempt++)); do
    log "fetch attempt $attempt/$FETCH_ATTEMPTS"
    if git fetch --prune origin "$BRANCH"; then
      return 0
    fi

    if ((attempt < FETCH_ATTEMPTS)); then
      delay=$((attempt * 5))
      log "fetch failed; retrying in ${delay}s"
      sleep "$delay"
    fi
  done

  return 1
}

check_url() {
  local label=$1
  local url=$2
  local attempt

  for ((attempt = 1; attempt <= 10; attempt++)); do
    if curl -fsS --max-time 10 -o /dev/null "$url"; then
      log "$label healthy: $url"
      return 0
    fi
    sleep 2
  done

  die "$label health check failed: $url"
}

for required_command in git docker curl ssh; do
  require_command "$required_command"
done

[[ -x "$GITHUB_SSH_WRAPPER" ]] || die "GitHub SSH wrapper missing or not executable: $GITHUB_SSH_WRAPPER"
export GIT_SSH="$GITHUB_SSH_WRAPPER"

cd "$REPO_DIR"

[[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || die "repository not found: $REPO_DIR"

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
[[ "$CURRENT_BRANCH" == "$BRANCH" ]] || die "expected branch $BRANCH; found ${CURRENT_BRANCH:-detached HEAD}"

GIT_DIR=$(git rev-parse --git-dir)
if [[ "$GIT_DIR" != /* ]]; then
  GIT_DIR="$REPO_DIR/$GIT_DIR"
fi

LOCK_DIR="$GIT_DIR/laoyao-deploy.lock"
mkdir "$LOCK_DIR" 2>/dev/null || die "another deployment is active: $LOCK_DIR"

STATE_DIR="$GIT_DIR/laoyao-deploy"
DEPLOYED_COMMIT_FILE="$STATE_DIR/deployed_commit"
mkdir -p "$STATE_DIR"

check_worktree

for required_path in DockerfileProd _config.laoyao.yml docker-compose.laoyao.yml docker/nginx.conf; do
  [[ -e "$required_path" ]] || die "server-local deployment file missing: $required_path"
done

docker compose -f "$COMPOSE_FILE" config >/dev/null

ORIGIN_URL=$(git config --get remote.origin.url || true)
if [[ "$ORIGIN_URL" != "$EXPECTED_REMOTE" ]]; then
  log "setting origin to $EXPECTED_REMOTE"
  git remote set-url origin "$EXPECTED_REMOTE"
fi

if ! fetch_main; then
  die "GitHub fetch failed after $FETCH_ATTEMPTS attempts; Docker build was skipped"
fi

BEFORE_COMMIT=$(git rev-parse HEAD)
TARGET_COMMIT=$(git rev-parse FETCH_HEAD)

if [[ "$BEFORE_COMMIT" != "$TARGET_COMMIT" ]]; then
  git merge-base --is-ancestor "$BEFORE_COMMIT" "$TARGET_COMMIT" || die "remote main is not a fast-forward from $BEFORE_COMMIT"

  printf '%s\n' "$BEFORE_COMMIT" > "$STATE_DIR/previous_commit.tmp"
  mv "$STATE_DIR/previous_commit.tmp" "$STATE_DIR/previous_commit"
  ROLLBACK_COMMIT="$BEFORE_COMMIT"

  log "updating source: $BEFORE_COMMIT -> $TARGET_COMMIT"
  git merge --ff-only "$TARGET_COMMIT"

  AFTER_COMMIT=$(git rev-parse HEAD)
  [[ "$AFTER_COMMIT" == "$TARGET_COMMIT" ]] || die "source verification failed: expected $TARGET_COMMIT; found $AFTER_COMMIT"
else
  AFTER_COMMIT="$BEFORE_COMMIT"
  log "source already current: $BEFORE_COMMIT"
fi

DEPLOYED_COMMIT=""
if [[ -f "$DEPLOYED_COMMIT_FILE" ]]; then
  DEPLOYED_COMMIT=$(head -n 1 "$DEPLOYED_COMMIT_FILE")
fi

if [[ "$DEPLOYED_COMMIT" == "$AFTER_COMMIT" ]]; then
  log "runtime already deployed: $DEPLOYED_COMMIT"
  docker compose -f "$COMPOSE_FILE" ps
  check_url "local" "$LOCAL_HEALTH_URL"
  check_url "public" "$PUBLIC_HEALTH_URL"
  log "deployment check complete"
  exit 0
fi

if [[ -n "$DEPLOYED_COMMIT" ]]; then
  log "runtime state differs: deployed $DEPLOYED_COMMIT; target $AFTER_COMMIT"
  if [[ -z "$ROLLBACK_COMMIT" ]] && git cat-file -e "$DEPLOYED_COMMIT^{commit}" 2>/dev/null; then
    ROLLBACK_COMMIT="$DEPLOYED_COMMIT"
  fi
else
  log "runtime state is not recorded; building target $AFTER_COMMIT"
fi

docker compose -f "$COMPOSE_FILE" config >/dev/null
docker compose -f "$COMPOSE_FILE" up -d --build
docker compose -f "$COMPOSE_FILE" ps
docker compose -f "$COMPOSE_FILE" logs --tail=80

check_url "local" "$LOCAL_HEALTH_URL"
check_url "public" "$PUBLIC_HEALTH_URL"

printf '%s\n' "$AFTER_COMMIT" > "$DEPLOYED_COMMIT_FILE.tmp"
mv "$DEPLOYED_COMMIT_FILE.tmp" "$DEPLOYED_COMMIT_FILE"

log "deployed successfully: $AFTER_COMMIT"
if [[ -n "$ROLLBACK_COMMIT" ]]; then
  log "rollback commit: $ROLLBACK_COMMIT"
fi
