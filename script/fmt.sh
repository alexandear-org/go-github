#!/bin/sh
#/ script/fmt.sh runs formatting on all Go files in the project.
#/ It uses custom golangci-lint to format the code.

set -e

CUSTOM_GCL="$(script/setup-custom-gcl.sh)"

CDPATH="" cd -- "$(dirname -- "$0")/.."

MOD_DIRS="$(git ls-files '*go.mod' | xargs dirname | sort)"

now_epoch() {
  date +%s
}

STAGE_NAME="fmt"
STAGE_START_EPOCH="$(now_epoch)"

for DIR in $MOD_DIRS; do
  MODULE_STAGE_NAME="$DIR"
  MODULE_START_EPOCH="$(now_epoch)"

  (
    cd "$DIR" > /dev/null
    "$CUSTOM_GCL" fmt
  )

  MODULE_END_EPOCH="$(now_epoch)"
  MODULE_ELAPSED=$((MODULE_END_EPOCH - MODULE_START_EPOCH))
  printf '[%s: %s] elapsed %ss\n' \
    "$STAGE_NAME" "$MODULE_STAGE_NAME" "$MODULE_ELAPSED"
done

STAGE_END_EPOCH="$(now_epoch)"
STAGE_ELAPSED=$((STAGE_END_EPOCH - STAGE_START_EPOCH))
printf '[%s] elapsed %ss\n' \
  "$STAGE_NAME" "$STAGE_ELAPSED"
