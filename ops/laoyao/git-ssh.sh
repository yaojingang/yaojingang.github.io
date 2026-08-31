#!/usr/bin/env bash

set -Eeuo pipefail

exec ssh \
  -i /root/.ssh/id_ed25519_laoyao_blog_github \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=15 \
  "$@"
