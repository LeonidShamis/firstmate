#!/usr/bin/env bash
# Manual reproduction of the reported defect: a freshly `git init`-ed project
# registered local-only, with NO remote, spawning a crewmate through the real
# bin/fm-spawn.sh with a fake tmux/treehouse. Runs the same fixture against the
# base commit tree (BEFORE) and the target tree (AFTER) and prints the transcript.
set -u
BEFORE_ROOT=${1:?base tree}; AFTER_ROOT=${2:?target tree}
WORK=$(mktemp -d /tmp/fm-manual-remote-less.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

make_fixture() {  # <dir> <id>
  local d=$1 id=$2
  mkdir -p "$d/home/data/$id" "$d/home/projects" "$d/home/state" "$d/home/config" "$d/fake"
  printf 'codex\n' > "$d/home/config/crew-harness"
  printf 'brief for %s\n' "$id" > "$d/home/data/$id/brief.md"
  touch "$d/home/state/.last-watcher-beat"
  cat > "$d/fake/tmux" <<'SH'
#!/usr/bin/env bash
case "$*" in *"#{pane_current_path}"*) printf '%s\n' "$FM_FAKE_PANE_PATH"; exit 0;; esac
case "${1:-}" in display-message) printf 'firstmate\n'; exit 0;; esac
exit 0
SH
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/fake/treehouse"
  chmod +x "$d/fake/tmux" "$d/fake/treehouse"
  git init --quiet -b main "$d/project"
  printf 'base\n' > "$d/project/README.md"
  git -C "$d/project" add README.md
  git -C "$d/project" -c user.name=t -c user.email=t@example.invalid commit -qm initial
  git -C "$d/project" worktree add --quiet --detach "$d/pool" HEAD
  printf 'advanced after pool allocation\n' > "$d/project/newer.txt"
  git -C "$d/project" add newer.txt
  git -C "$d/project" -c user.name=t -c user.email=t@example.invalid commit -qm advance-main
}

run_case() {  # <label> <root> <id>
  local label=$1 root=$2 id=$3 d="$WORK/$1" out status
  make_fixture "$d" "$id"
  echo "=== $label: $root/bin/fm-spawn.sh"
  echo "\$ git -C project remote            # (prints nothing: no remote at all)"
  git -C "$d/project" remote
  echo "\$ git -C project log --oneline main"
  git -C "$d/project" log --oneline main
  echo "\$ git -C pool rev-parse HEAD        # pool slot before spawn (stale base)"
  git -C "$d/pool" rev-parse HEAD
  echo "\$ fm-spawn.sh $id project --mode local-only --yolo off"
  out=$(FM_GATE_REFUSE_BYPASS=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    FM_ROOT_OVERRIDE='' FM_HOME="$d/home" \
    FM_STATE_OVERRIDE="$d/home/state" FM_DATA_OVERRIDE="$d/home/data" \
    FM_PROJECTS_OVERRIDE="$d/home/projects" FM_CONFIG_OVERRIDE="$d/home/config" \
    FM_SPAWN_NO_GUARD=1 TMUX="fake,1,0" FM_FAKE_PANE_PATH="$d/pool" \
    PATH="$d/fake:$PATH" \
    "$root/bin/fm-spawn.sh" "$id" "$d/project" --mode local-only --yolo off 2>&1)
  status=$?
  printf '%s\n' "$out"
  echo "exit=$status"
  echo "\$ git -C pool rev-parse HEAD        # pool slot after spawn"
  git -C "$d/pool" rev-parse HEAD
  echo "\$ git -C pool branch --show-current"
  git -C "$d/pool" branch --show-current
  echo "\$ ls pool"
  ls "$d/pool"
  echo
}

run_case BEFORE "$BEFORE_ROOT" local-only-before
run_case AFTER "$AFTER_ROOT" local-only-after
