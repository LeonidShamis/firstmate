#!/usr/bin/env bash
# Evidence helper: run named test functions from tests/fm-teardown.test.sh one at a
# time, each in a fresh shell, so one failing case cannot abort the others.
# usage: run-selected-teardown-tests.sh <tests-dir> <test-fn>...
# When EVIDENCE_COPY_DIR is set, every per-case transcript (stdout/stderr files,
# treehouse.log, and the surviving state/*.meta records) is copied there before the
# case sandbox is removed.
tests_dir=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
cut=$(grep -n '^test_local_only_fork_remote_allows$' "$tests_dir/fm-teardown.test.sh" | head -1 | cut -d: -f1)
for t in "$@"; do
  ( cd "$tests_dir" && bash "$here/run-one-teardown-test.sh" "$cut" "$t" ); echo "[$t] exit=$?"
done
