#!/bin/sh
#/ [ CHECK_GITHUB_OPENAPI=1 ] script/lint.sh runs linters and validates generated files.
#/ When CHECK_GITHUB is set, it validates that openapi_operations.yaml is consistent with the
#/ descriptions from github.com/github/rest-api-description.

set -e

CDPATH="" cd -- "$(dirname -- "$0")/.."

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
  printf '[%s] elapsed %ss\n' "$STAGE_NAME" "$STAGE_ELAPSED"
}

EXIT_CODE=0

MAIN_STAGE_NAME="lint"
MAIN_STAGE_START_EPOCH="$(now_epoch)"

# Colors & Formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

fail() {
  EXIT_CODE=1
}

MOD_DIRS="$(git ls-files '*go.mod' | xargs dirname | sort -u)"

# Number of module lint jobs to run concurrently.
# Override with LINT_JOBS, otherwise use detected CPU count.
: "${LINT_JOBS:=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

LINT_DIRS="$(printf '%s\n' "$MOD_DIRS" | grep -v '^example/newreposecretwithlibsodium$')"

FAILED_COUNT=0
RUNNING=0
PIDS=""
DIRS_IN_FLIGHT=""
STARTS_IN_FLIGHT=""

LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT

print_header() {
  printf "${BOLD}%s${NC}\n\n" "$1"
}

wait_pids() {
  I=1
  for PID in $PIDS; do
    # Identify the directory for this PID
    DIR=$(echo "$DIRS_IN_FLIGHT" | awk -v i="$I" '{print $i}')
    MODULE_START_EPOCH=$(echo "$STARTS_IN_FLIGHT" | awk -v i="$I" '{print $i}')
    LOG_FILE="$LOG_DIR/$(echo "$DIR" | tr '/' '_').log"
    MODULE_ELAPSED=$(( $(now_epoch) - MODULE_START_EPOCH ))

    if wait "$PID"; then
      printf "${GREEN}✔ %-40s [ PASS ] elapsed %ss${NC}\n" "$DIR" "$MODULE_ELAPSED"
    else
      printf "${RED}✘ %-40s [ FAIL ] elapsed %ss${NC}\n" "$DIR" "$MODULE_ELAPSED"
      if [ -f "$LOG_FILE" ]; then
        sed 's/^/    /' "$LOG_FILE"
      fi
      FAILED_COUNT=$((FAILED_COUNT + 1))
      fail
    fi
    I=$((I + 1))
  done
  PIDS=""
  DIRS_IN_FLIGHT=""
  STARTS_IN_FLIGHT=""
  RUNNING=0
}

print_header "Setup custom golangci-lint"

start_stage "custom-gcl"
CUSTOM_GCL="$(script/setup-custom-gcl.sh)"
end_stage

print_header "Linting modules"

for DIR in $LINT_DIRS; do
  MODULE_START_EPOCH="$(now_epoch)"
  LOG_FILE="$LOG_DIR/$(echo "$DIR" | tr '/' '_').log"

  # Run the linter in the background and redirect output to a log file
  (cd "$DIR" > /dev/null && "$CUSTOM_GCL" run --color always > "$LOG_FILE" 2>&1) &

  PIDS="$PIDS $!"
  DIRS_IN_FLIGHT="$DIRS_IN_FLIGHT $DIR"
  STARTS_IN_FLIGHT="$STARTS_IN_FLIGHT $MODULE_START_EPOCH"
  RUNNING=$((RUNNING + 1))

  if [ "$RUNNING" -ge "$LINT_JOBS" ]; then
    wait_pids
  fi
done

wait_pids

if [ -n "$CHECK_GITHUB_OPENAPI" ]; then
  print_header "Validating openapi_operations.yaml"
  start_stage "openapi"
  if script/metadata.sh update-openapi --validate; then
    printf "${GREEN}✔ openapi_operations.yaml is valid${NC}\n"
  else
    printf "${RED}✘ openapi_operations.yaml validation failed${NC}\n"
    fail
  fi
  end_stage
fi

print_header "Validating generated files"
start_stage "generate"
if script/generate.sh --check; then
  printf "${GREEN}✔ Generated files are up to date${NC}\n"
else
  printf "${RED}✘ Generated files out of sync${NC}\n"
  fail
fi
end_stage

# --- Final Summary ---
printf -- "----------------------------\n"
SUMMARY_COLOR="$GREEN"
if [ "$FAILED_COUNT" -gt 0 ]; then
  SUMMARY_COLOR="$RED"
fi

printf "%bLinting: issues found in %d module directories.%b\n" "$SUMMARY_COLOR" "$FAILED_COUNT" "$NC"
printf -- "--------------------------------------------\n"

STAGE_NAME="$MAIN_STAGE_NAME"
STAGE_START_EPOCH="$MAIN_STAGE_START_EPOCH"
end_stage

exit "$EXIT_CODE"
