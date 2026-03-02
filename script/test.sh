#!/bin/sh
#/ script/test.sh runs tests on each go module in go-github. Arguments are passed to each go test invocation.
#/ "-race -covermode atomic ./..." is used when no arguments are given.
#/
#/ When UPDATE_GOLDEN is set, all directories named "golden" are removed before running tests.

set -e

# Handle interruption (Ctrl+C)
INTERRUPTED=0
trap 'INTERRUPTED=1' INT

CDPATH="" cd -- "$(dirname -- "$0")/.."

if [ "$#" = "0" ]; then
  set -- -race -covermode atomic ./...
fi

if [ -n "$UPDATE_GOLDEN" ]; then
  find . -name golden -type d -exec rm -rf {} +
fi

MOD_DIRS="$(git ls-files '*go.mod' | xargs dirname | sort)"

for dir in $MOD_DIRS; do
  [ "$INTERRUPTED" = "1" ] && break
  [ "$dir" = "example/newreposecretwithlibsodium" ] && continue
  echo "testing $dir"
  (
    cd "$dir"
    go test "$@"
  ) || FAILED=1
done

if [ "$INTERRUPTED" = "1" ]; then
  exit 130
fi

if [ -n "$FAILED" ]; then
  exit 1
fi
