#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/laoyao-deploy-tests.XXXXXX")

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local expected=$2
  grep -Fq "$expected" "$file" || fail "$file does not contain: $expected"
}

assert_not_contains() {
  local file=$1
  local unexpected=$2
  if grep -Fq "$unexpected" "$file"; then
    fail "$file contains unexpected text: $unexpected"
  fi
}

create_fake_commands() {
  local case_dir=$1
  local fake_bin="$case_dir/fake-bin"

  mkdir -p "$fake_bin"

  cat > "$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DEPLOY_TEST_LOG/docker.log"
SH

  cat > "$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DEPLOY_TEST_LOG/curl.log"
SH

  cat > "$fake_bin/sleep" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DEPLOY_TEST_LOG/sleep.log"
SH

  chmod +x "$fake_bin/docker" "$fake_bin/curl" "$fake_bin/sleep"
}

create_fixture() {
  local name=$1

  CASE_DIR="$TEST_ROOT/$name"
  UPSTREAM_DIR="$CASE_DIR/upstream.git"
  AUTHOR_DIR="$CASE_DIR/author"
  SERVER_DIR="$CASE_DIR/server"
  LOG_DIR="$CASE_DIR/logs"
  OUTPUT_FILE="$CASE_DIR/output.log"
  FAKE_BIN="$CASE_DIR/fake-bin"

  mkdir -p "$CASE_DIR" "$LOG_DIR"
  : > "$LOG_DIR/docker.log"
  : > "$LOG_DIR/curl.log"
  : > "$LOG_DIR/sleep.log"

  git init --bare -q "$UPSTREAM_DIR"
  git init -q "$AUTHOR_DIR"
  git -C "$AUTHOR_DIR" config user.name "Deploy Test"
  git -C "$AUTHOR_DIR" config user.email "deploy-test@example.com"
  git -C "$AUTHOR_DIR" checkout -q -b main

  mkdir -p "$AUTHOR_DIR/ops/laoyao"
  cp "$DEPLOY_SCRIPT" "$AUTHOR_DIR/ops/laoyao/deploy.sh"
  cp "$SCRIPT_DIR/git-ssh.sh" "$AUTHOR_DIR/ops/laoyao/git-ssh.sh"
  chmod +x "$AUTHOR_DIR/ops/laoyao/git-ssh.sh"
  sed -i.bak "s#^EXPECTED_REMOTE=.*#EXPECTED_REMOTE=\"$UPSTREAM_DIR\"#" "$AUTHOR_DIR/ops/laoyao/deploy.sh"
  rm "$AUTHOR_DIR/ops/laoyao/deploy.sh.bak"

  printf 'base\n' > "$AUTHOR_DIR/README.md"
  git -C "$AUTHOR_DIR" add README.md ops/laoyao/deploy.sh ops/laoyao/git-ssh.sh
  git -C "$AUTHOR_DIR" commit -q -m "Base fixture"
  git -C "$AUTHOR_DIR" remote add origin "$UPSTREAM_DIR"
  git -C "$AUTHOR_DIR" push -q -u origin main
  git --git-dir="$UPSTREAM_DIR" symbolic-ref HEAD refs/heads/main

  git clone -q "$UPSTREAM_DIR" "$SERVER_DIR"

  mkdir -p "$SERVER_DIR/docker"
  : > "$SERVER_DIR/DockerfileProd"
  : > "$SERVER_DIR/_config.laoyao.yml"
  : > "$SERVER_DIR/docker-compose.laoyao.yml"
  : > "$SERVER_DIR/docker/nginx.conf"

  create_fake_commands "$CASE_DIR"
}

run_deploy() {
  PATH="$FAKE_BIN:$PATH" \
    DEPLOY_TEST_LOG="$LOG_DIR" \
    bash "$SERVER_DIR/ops/laoyao/deploy.sh" > "$OUTPUT_FILE" 2>&1
}

test_successful_update() {
  create_fixture "successful-update"

  printf 'update\n' >> "$AUTHOR_DIR/README.md"
  git -C "$AUTHOR_DIR" add README.md
  git -C "$AUTHOR_DIR" commit -q -m "Update fixture"
  git -C "$AUTHOR_DIR" push -q origin main

  run_deploy

  local server_head upstream_head
  server_head=$(git -C "$SERVER_DIR" rev-parse HEAD)
  upstream_head=$(git --git-dir="$UPSTREAM_DIR" rev-parse refs/heads/main)

  [[ "$server_head" == "$upstream_head" ]] || fail "server did not reach upstream head"
  assert_contains "$LOG_DIR/docker.log" "compose -f docker-compose.laoyao.yml up -d --build"
  assert_contains "$OUTPUT_FILE" "deployed successfully"
  [[ "$(cat "$SERVER_DIR/.git/laoyao-deploy/deployed_commit")" == "$server_head" ]] || fail "deployed commit state was not recorded"
  printf 'PASS: successful update\n'
}

test_fetch_failure_skips_build() {
  create_fixture "fetch-failure"
  mv "$UPSTREAM_DIR" "$CASE_DIR/upstream-offline.git"

  if run_deploy; then
    fail "fetch failure unexpectedly succeeded"
  fi

  assert_not_contains "$LOG_DIR/docker.log" "up -d --build"
  assert_contains "$OUTPUT_FILE" "Docker build was skipped"
  assert_contains "$LOG_DIR/sleep.log" "5"
  assert_contains "$LOG_DIR/sleep.log" "10"
  printf 'PASS: fetch failure skips build\n'
}

test_remote_url_is_repaired() {
  create_fixture "remote-repair"
  mkdir -p "$SERVER_DIR/.git/laoyao-deploy"
  git -C "$SERVER_DIR" rev-parse HEAD > "$SERVER_DIR/.git/laoyao-deploy/deployed_commit"
  git -C "$SERVER_DIR" remote set-url origin "$CASE_DIR/wrong-origin.git"

  run_deploy

  [[ "$(git -C "$SERVER_DIR" config --get remote.origin.url)" == "$UPSTREAM_DIR" ]] || fail "origin URL was not repaired"
  assert_contains "$OUTPUT_FILE" "setting origin to"
  printf 'PASS: remote URL is repaired\n'
}

test_current_source_skips_build() {
  create_fixture "current-source"
  mkdir -p "$SERVER_DIR/.git/laoyao-deploy"
  git -C "$SERVER_DIR" rev-parse HEAD > "$SERVER_DIR/.git/laoyao-deploy/deployed_commit"

  run_deploy

  assert_not_contains "$LOG_DIR/docker.log" "up -d --build"
  assert_contains "$LOG_DIR/docker.log" "compose -f docker-compose.laoyao.yml ps"
  assert_contains "$OUTPUT_FILE" "source already current"
  printf 'PASS: current source skips build\n'
}

test_missing_runtime_state_rebuilds() {
  create_fixture "missing-runtime-state"

  run_deploy

  local server_head
  server_head=$(git -C "$SERVER_DIR" rev-parse HEAD)

  assert_contains "$LOG_DIR/docker.log" "compose -f docker-compose.laoyao.yml up -d --build"
  assert_contains "$OUTPUT_FILE" "runtime state is not recorded"
  [[ "$(cat "$SERVER_DIR/.git/laoyao-deploy/deployed_commit")" == "$server_head" ]] || fail "bootstrap deployment state was not recorded"
  printf 'PASS: missing runtime state rebuilds\n'
}

test_rollback_state_rebuilds_current_source() {
  create_fixture "rollback-state"

  local rollback_commit target_commit
  rollback_commit=$(git -C "$SERVER_DIR" rev-parse HEAD)

  printf 'update\n' >> "$AUTHOR_DIR/README.md"
  git -C "$AUTHOR_DIR" add README.md
  git -C "$AUTHOR_DIR" commit -q -m "Update fixture"
  git -C "$AUTHOR_DIR" push -q origin main

  git -C "$SERVER_DIR" pull -q --ff-only origin main
  target_commit=$(git -C "$SERVER_DIR" rev-parse HEAD)
  mkdir -p "$SERVER_DIR/.git/laoyao-deploy"
  printf '%s\n' "$rollback_commit" > "$SERVER_DIR/.git/laoyao-deploy/deployed_commit"

  run_deploy

  assert_contains "$LOG_DIR/docker.log" "compose -f docker-compose.laoyao.yml up -d --build"
  assert_contains "$OUTPUT_FILE" "runtime state differs"
  [[ "$(cat "$SERVER_DIR/.git/laoyao-deploy/deployed_commit")" == "$target_commit" ]] || fail "rollback recovery state was not updated"
  printf 'PASS: rollback state rebuilds current source\n'
}

test_tracked_change_stops_deploy() {
  create_fixture "tracked-change"
  printf 'local change\n' >> "$SERVER_DIR/README.md"

  if run_deploy; then
    fail "tracked change unexpectedly succeeded"
  fi

  assert_not_contains "$LOG_DIR/docker.log" "up -d --build"
  assert_contains "$OUTPUT_FILE" "tracked working-tree changes detected"
  printf 'PASS: tracked change stops deploy\n'
}

test_successful_update
test_fetch_failure_skips_build
test_remote_url_is_repaired
test_current_source_skips_build
test_missing_runtime_state_rebuilds
test_rollback_state_rebuilds_current_source
test_tracked_change_stops_deploy

printf 'PASS: 7 deployment tests\n'
