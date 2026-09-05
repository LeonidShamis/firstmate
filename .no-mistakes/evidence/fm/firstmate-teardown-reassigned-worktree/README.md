# Test evidence: teardown never tears down a worktree reassigned to another task

Branch fm/firstmate-teardown-reassigned-worktree, target 7467a90 against base c03bfbe.
Host note: lsof is not installed on this host, which is why the five real-lsof reap cases fail identically on base and target.

## Product-level transcripts (bin/fm-teardown.sh stderr/stdout, pool return log, persisted meta)

- transcripts/reassigned-worktree-refusal/ (target): first.stderr is the partial run (return succeeded, later step failed), second.stderr is the rerun refusing because task-x2's record claims the worktree, third.stderr is the rerun refusing because the worktree's .fm-task-owner marker names task-x2, treehouse.log shows exactly one pool return across all three runs.
- transcripts-base-c03bfbe/reassigned-worktree-refusal/ (base, same scenario): second.stderr shows the rerun reaping the successor task's process and treehouse.log shows the slot returned twice, which is the reported defect.
- transcripts/reconciled-rerun/ (target): second.stderr shows the rerun skipping every worktree step, second.stdout shows it completing, treehouse.log shows one return.
- transcripts-base-c03bfbe/reconciled-rerun/ (base): treehouse.log shows the rerun returning the already-returned slot a second time.
- transcripts/own-worktree-return/ (target): an ordinary teardown still reaps its own leaked process and returns its own worktree.
- converged-meta-transcript.txt: state/task-x1.meta before and after a real partial failure, showing worktree_returned=1 recorded, and an unreconciled rerun skipping the worktree steps with still one pool return.

## Suite logs

- fm-teardown.test.log: full tests/fm-teardown.test.sh run on target (stops at the pre-existing lsof failure after the new cases pass).
- fm-teardown-ownership-cases.log and fm-teardown-ownership-cases-base-c03bfbe.log: the three new regression cases on target (pass) and on base scripts (the two defect cases fail, the ordinary case passes).
- fm-teardown-remaining-cases-target.log and fm-teardown-remaining-cases-base-c03bfbe.log: the ten reap cases that follow the lsof failure, run one at a time on target and base, with identical results.
- fm-control-relaunch.test.log, fm-spawn-worktree-settle.test.log, fm-teardown-endpoint-safety.test.log, fm-backend-orca.test.log: full runs of the other touched or adjacent suites, all passing.

## Helpers used to produce the evidence

- run-selected-teardown-tests.sh and run-one-teardown-test.sh: run named test functions of tests/fm-teardown.test.sh individually and copy each case sandbox's transcripts out before cleanup.
- show-converged-meta.sh: drives one real partial-failure teardown with the suite's fixtures and prints the persisted meta.
