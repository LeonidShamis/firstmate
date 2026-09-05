#!/usr/bin/env bash
# Evidence helper: drive one real partial-failure teardown through bin/fm-teardown.sh
# using the suite's own fixtures (pool return succeeds, the grok turn-end removal that
# runs after it fails) and print the persisted state/<id>.meta record afterwards.
# Must run with cwd = tests dir.
cut=$(grep -n '^test_local_only_fork_remote_allows$' fm-teardown.test.sh | head -1 | cut -d: -f1)
defs=$(sed -n "1,$(( cut - 1 ))p" fm-teardown.test.sh | sed 's#\$(dirname "\${BASH_SOURCE\[0\]}")/lib.sh#./lib.sh#')
eval "$defs"
case_dir=$(make_case converged-meta-demo)
write_meta "$case_dir" no-mistakes ship
land_shippable_commit "$case_dir"
add_return_logging_treehouse "$case_dir"
add_lsof_cwd_map "$case_dir"
echo "## state/task-x1.meta before teardown"; cat "$case_dir/state/task-x1.meta"
echo "## worktree marker before teardown (.fm-task-owner)"; cat "$case_dir/wt/.fm-task-owner" 2>/dev/null || echo "(none: fixture worktree was not spawned by fm-spawn.sh)"
break_step_after_worktree_return "$case_dir"
rc=0; run_teardown "$case_dir" > "$case_dir/stdout" 2> "$case_dir/stderr" || rc=$?
echo "## first teardown exit=$rc (pool return succeeded, later step failed)"
echo "## treehouse calls so far"; cat "$case_dir/treehouse.log"
echo "## state/task-x1.meta after the partial failure (record retained and converged)"; cat "$case_dir/state/task-x1.meta"
echo "## rerun without reconciling: exit and stderr"
rc=0; run_teardown "$case_dir" > "$case_dir/stdout2" 2> "$case_dir/stderr2" || rc=$?
echo "exit=$rc"; cat "$case_dir/stderr2"
echo "## treehouse calls after the unreconciled rerun (must still be one)"; cat "$case_dir/treehouse.log"
