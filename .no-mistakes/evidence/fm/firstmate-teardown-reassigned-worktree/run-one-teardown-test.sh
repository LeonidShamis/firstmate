#!/usr/bin/env bash
# Inner helper for run-selected-teardown-tests.sh. Must run with cwd = tests dir.
# Loads every definition of fm-teardown.test.sh above its invocation list (the
# lib.sh include is rewritten to a cwd-relative path) and runs one test function.
cut=$1; fn=$2
defs=$(sed -n "1,$(( cut - 1 ))p" fm-teardown.test.sh | sed 's#\$(dirname "\${BASH_SOURCE\[0\]}")/lib.sh#./lib.sh#')
eval "$defs"
copy_transcripts() {
  [ -n "${EVIDENCE_COPY_DIR:-}" ] || return 0
  for c in "$TMP_ROOT"/*/; do
    n=$(basename "$c"); mkdir -p "$EVIDENCE_COPY_DIR/$n"
    cp "$c"/*.stdout "$c"/*.stderr "$c"/stdout "$c"/stderr "$c"/treehouse.log "$EVIDENCE_COPY_DIR/$n/" 2>/dev/null || true
    cp "$c"/state/*.meta "$EVIDENCE_COPY_DIR/$n/" 2>/dev/null || true
  done
}
# The suite's fail() exits the shell, so copy from an EXIT trap; lib.sh's own
# cleanup trap is armed at source time, so chain it rather than replace it.
prior_trap=$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT$/\1/")
trap 'copy_transcripts; eval "$prior_trap"' EXIT
"$fn"
