#!/bin/sh
#/ `script/generate.sh` runs `go generate` on all modules in this repo.
#/ It also runs `script/run-check-structfield-settings.sh -fix` to keep linter
#/ exceptions in `.golangci.yml` up to date.
#/ `script/generate.sh --check` checks that the generated files are up to date.

set -e

CDPATH="" cd -- "$(dirname -- "$0")/.."

# Colors & Formatting
RED='\033[0;31m'
NC='\033[0m'

now_epoch() {
  date +%s
}

if [ "$1" = "--check" ]; then
  GENTEMP="$(mktemp -d)"
  git worktree add -q --detach "$GENTEMP"
  trap 'git worktree remove -f "$GENTEMP"; rm -rf "$GENTEMP"' EXIT
  git diff --name-only --diff-filter=D --no-renames HEAD | while read -r f; do
    rm -f "$GENTEMP/$f"
  done
  git ls-files -com --exclude-standard | while read -r f; do
    target="$GENTEMP/$f"
    mkdir -p "$(dirname -- "$target")"
    cp "$f" "$target"
  done
  if [ -f "$(pwd)"/bin ]; then
    ln -s "$(pwd)"/bin "$GENTEMP"/bin
  fi
  (
    cd "$GENTEMP"
    git add .
    git -c user.name='bot' -c user.email='bot@localhost' -c commit.gpgsign=false commit -m "generate" -q --allow-empty
    script/generate.sh
    [ -z "$(git status --porcelain)" ] || {
      msg="Generated files are out of date. Please run script/generate.sh and commit the results"
      if [ -n "$GITHUB_ACTIONS" ]; then
        echo "::error ::$msg"
      else
        printf "${RED}%s${NC}\n" "$msg" 1>&2
      fi
      git diff
      exit 1
    }
  )
  exit 0
fi

STAGE_NAME="generate"
STAGE_START_EPOCH="$(now_epoch)"

MOD_DIRS="$(git ls-files '*go.mod' | xargs dirname | sort)"

for DIR in $MOD_DIRS; do
  MODULE_STAGE_NAME="$DIR"
  MODULE_START_EPOCH="$(now_epoch)"

  (
    cd "$DIR" > /dev/null
    go generate ./...
    go mod tidy
  )

  MODULE_END_EPOCH="$(now_epoch)"
  MODULE_ELAPSED=$((MODULE_END_EPOCH - MODULE_START_EPOCH))
  printf '[%s: %s] elapsed %ss\n' \
    "$STAGE_NAME" "$MODULE_STAGE_NAME" "$MODULE_ELAPSED"
done

STRUCTFIELD_STAGE_NAME="check-structfield-settings"
STRUCTFIELD_START_EPOCH="$(now_epoch)"
script/run-check-structfield-settings.sh -fix
STRUCTFIELD_END_EPOCH="$(now_epoch)"
STRUCTFIELD_ELAPSED=$((STRUCTFIELD_END_EPOCH - STRUCTFIELD_START_EPOCH))
printf '[%s: %s] elapsed %ss\n' \
  "$STAGE_NAME" "$STRUCTFIELD_STAGE_NAME" "$STRUCTFIELD_ELAPSED"

STAGE_END_EPOCH="$(now_epoch)"
STAGE_ELAPSED=$((STAGE_END_EPOCH - STAGE_START_EPOCH))
printf '[%s] elapsed %ss\n' \
  "$STAGE_NAME" "$STAGE_ELAPSED"
