#!/bin/sh
#/ script/setup-custom-gcl.sh ensures custom golangci-lint is installed.
#/ It returns the path to the custom-gcl binary.

set -e

now_epoch() {
  date +%s
}

start_stage() {
  STAGE_NAME="$1"
  STAGE_START_EPOCH="$(now_epoch)"
}

end_stage() {
  STAGE_END_EPOCH="$(now_epoch)"
  STAGE_ELAPSED=$((STAGE_END_EPOCH - STAGE_START_EPOCH))
  printf '[%s] elapsed %ss\n' "$STAGE_NAME" "$STAGE_ELAPSED" 1>&2
}

# should be in sync with .custom-gcl.yml
GOLANGCI_LINT_VERSION="v2.10.1"

# should in sync with fmt.sh and lint.sh
BIN="$(pwd -P)"/bin

mkdir -p "$BIN"

# install golangci-lint and custom-gcl in ./bin if they don't exist with the correct version
if ! "$BIN"/custom-gcl version --short 2> /dev/null | grep -q "$GOLANGCI_LINT_VERSION"; then
  start_stage "gcl: install"
  curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b "$BIN" "$GOLANGCI_LINT_VERSION"
  end_stage

  start_stage "gcl: build"
  "$BIN"/golangci-lint custom --name custom-gcl --destination "$BIN"
  end_stage
fi

echo "$BIN/custom-gcl"
