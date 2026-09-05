#!/usr/bin/env bash
# The beads-storage refusal shared by the three secondmate backlog movers:
# local handoff and remote outbox staging in bin/fm-backlog-handoff.sh, and
# receipt in bin/fm-backlog-receive.sh.
#
# All three move item blocks between explicit markdown files. On beads storage
# data/backlog.md is a mirror tasks-axi regenerates from the database, so a
# block move out of it diverges the two stores as soon as the next render runs.
# Each mover therefore refuses on the storage the home's own .tasks.toml
# DECLARES. That question must not be answerable by the ambient environment:
# every mover pins TASKS_AXI_BACKEND=markdown on its own tasks-axi calls, so an
# operator shell exporting the same variable (or exporting it empty) would
# otherwise satisfy the gate and let the pinned move run against the mirror.
# This suite owns that contract for all three entry points; the surrounding
# handoff behavior lives in tests/fm-backlog-handoff.test.sh and
# tests/fm-remote-backlog-handoff.test.sh.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/secondmate-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/secondmate-helpers.sh"

command -v tasks-axi >/dev/null 2>&1 || { echo "skip: tasks-axi not found"; exit 0; }

TMP_ROOT=$(fm_test_tmproot fm-backlog-beads-guard)

# The three ambient states the gate must answer identically: no override at
# all, the same override every mover pins on its own calls, and the empty
# value that a `${VAR+x}` precedence check still treats as set.
AMBIENT_CASES=(unset markdown empty)

# Run <cmd...> with TASKS_AXI_BACKEND in the named ambient state.
with_ambient() {  # <case> <cmd...>
  local ambient=$1
  shift
  case "$ambient" in
    unset) env -u TASKS_AXI_BACKEND "$@" ;;
    markdown) env TASKS_AXI_BACKEND=markdown "$@" ;;
    empty) env TASKS_AXI_BACKEND= "$@" ;;
    *) fail "unknown ambient case: $ambient" ;;
  esac
}

# A beads-storage primary and one seeded secondmate, both holding a markdown
# backlog file so the only thing that can refuse the move is the declared
# storage.
make_beads_primary() {  # <name> <secondmate-id>
  local home="$TMP_ROOT/$1" sub="$TMP_ROOT/$1-sub" id=$2 sub_abs
  mkdir -p "$home/data" "$home/state"
  seed_secondmate_home_marker "$sub" "$id"
  sub_abs=$(cd "$sub" && pwd -P)
  cat > "$home/data/backlog.md" <<'EOF'
## In flight

## Queued
- [ ] guarded-item - routed nowhere (repo: alpha)

## Done
EOF
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$sub/data/backlog.md"
  printf 'backend = "beads"\n\n[beads]\ndir = "data"\n' > "$home/.tasks.toml"
  printf '%s\n' "$home|$sub_abs"
}

test_local_handoff_refuses_beads_storage_under_any_ambient_backend() {
  local ambient fixture home sub out rc
  for ambient in "${AMBIENT_CASES[@]}"; do
    fixture=$(make_beads_primary "local-$ambient" design)
    home=${fixture%%|*}
    sub=${fixture##*|}
    printf -- '- design - feature work (home: %s; scope: feature work; projects: alpha; added 2026-09-06)\n' \
      "$sub" > "$home/data/secondmates.md"
    rc=0
    out=$(with_ambient "$ambient" env FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
      "$ROOT/bin/fm-backlog-handoff.sh" design guarded-item 2>&1) || rc=$?
    [ "$rc" -ne 0 ] \
      || fail "local handoff accepted beads storage with TASKS_AXI_BACKEND $ambient (got: $out)"
    assert_contains "$out" 'requires markdown backlog storage' \
      "the $ambient refusal must name the storage requirement (got: $out)"
    assert_grep 'guarded-item' "$home/data/backlog.md" \
      "the $ambient refusal moved the item out of the beads mirror"
    assert_no_grep 'guarded-item' "$sub/data/backlog.md" \
      "the $ambient refusal wrote the destination backlog"
  done
  pass "local handoff refuses beads storage whatever TASKS_AXI_BACKEND says"
}

test_remote_outbox_staging_refuses_beads_storage_under_any_ambient_backend() {
  local ambient fixture home sub out rc outbox
  for ambient in "${AMBIENT_CASES[@]}"; do
    fixture=$(make_beads_primary "remote-$ambient" edge)
    home=${fixture%%|*}
    sub=${fixture##*|}
    printf -- '- edge - feature work (host: fixture-host; root: /srv/fm; home: %s; scope: feature work; projects: alpha; added 2026-09-06)\n' \
      "$sub" > "$home/data/secondmates.md"
    outbox="$home/data/handoff/edge.outbox.md"
    rc=0
    out=$(with_ambient "$ambient" env FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
      "$ROOT/bin/fm-backlog-handoff.sh" edge guarded-item 2>&1) || rc=$?
    [ "$rc" -ne 0 ] \
      || fail "remote staging accepted beads storage with TASKS_AXI_BACKEND $ambient (got: $out)"
    assert_contains "$out" 'requires markdown backlog storage' \
      "the $ambient remote refusal must name the storage requirement (got: $out)"
    assert_grep 'guarded-item' "$home/data/backlog.md" \
      "the $ambient remote refusal staged the item out of the beads mirror"
    assert_absent "$outbox" "the $ambient remote refusal created an outbox anyway"
  done
  pass "remote outbox staging refuses beads storage whatever TASKS_AXI_BACKEND says"
}

# A seeded secondmate home on beads storage, holding a delivered outbox whose
# byte count and digest are correct, so receipt is refused only by storage.
make_beads_receiver() {  # <name>
  local home="$TMP_ROOT/$1" delivered bytes hash
  seed_secondmate_home_marker "$home" mate
  mkdir -p "$home/state/handoff" "$home/bin"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  printf 'backend = "beads"\n\n[beads]\ndir = "data"\n' > "$home/.tasks.toml"
  delivered="$home/state/handoff/mate.outbox.md"
  cat > "$delivered" <<'EOF'
## Queued
- [ ] delivered-item - routed work (repo: alpha)
EOF
  bytes=$(wc -c < "$delivered" | tr -d '[:space:]')
  if command -v shasum >/dev/null 2>&1; then
    hash=$(shasum -a 256 "$delivered" | awk '{print $1}')
  else
    hash=$(sha256sum "$delivered" | awk '{print $1}')
  fi
  printf '%s|%s|%s\n' "$home" "$bytes" "$hash"
}

test_receive_refuses_beads_storage_under_any_ambient_backend() {
  local ambient fixture home bytes hash out rc
  for ambient in "${AMBIENT_CASES[@]}"; do
    fixture=$(make_beads_receiver "receive-$ambient")
    home=${fixture%%|*}
    bytes=$(printf '%s' "$fixture" | cut -d'|' -f2)
    hash=$(printf '%s' "$fixture" | cut -d'|' -f3)
    rc=0
    out=$(with_ambient "$ambient" env FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
      "$ROOT/bin/fm-backlog-receive.sh" state/handoff/mate.outbox.md \
      "$bytes" "$hash" 1 2>&1) || rc=$?
    [ "$rc" -ne 0 ] \
      || fail "receive accepted beads storage with TASKS_AXI_BACKEND $ambient (got: $out)"
    assert_contains "$out" 'requires markdown backlog storage' \
      "the $ambient receive refusal must name the storage requirement (got: $out)"
    assert_no_grep 'delivered-item' "$home/data/backlog.md" \
      "the $ambient receive refusal merged into the beads mirror"
    assert_present "$home/state/handoff/mate.outbox.md" \
      "the $ambient receive refusal consumed the delivered outbox"
  done
  pass "receive refuses beads storage whatever TASKS_AXI_BACKEND says"
}

# The gate reads the home's own declared storage, so a markdown home is still
# allowed to move work even when the ambient environment names beads.
test_markdown_home_is_not_refused_by_an_ambient_beads_override() {
  local fixture home sub out
  fixture=$(make_beads_primary markdown-home design)
  home=${fixture%%|*}
  sub=${fixture##*|}
  fm_test_markdown_tasks_toml "$home"
  printf -- '- design - feature work (home: %s; scope: feature work; projects: alpha; added 2026-09-06)\n' \
    "$sub" > "$home/data/secondmates.md"
  # No live receiver endpoint is recorded in this fixture, so the run still
  # ends non-zero on the wake; what matters is that the storage gate let the
  # move happen and the item is durable in the destination backlog.
  out=$(env TASKS_AXI_BACKEND=beads FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/fm-backlog-handoff.sh" design guarded-item 2>&1) || true
  assert_not_contains "$out" 'requires markdown backlog storage' \
    "an ambient beads override must not refuse a declared markdown home (got: $out)"
  assert_grep 'guarded-item' "$sub/data/backlog.md" \
    "the declared markdown home did not deliver the item"
  assert_no_grep 'guarded-item' "$home/data/backlog.md" \
    "the declared markdown home kept the item it handed off"
  pass "a declared markdown home is unaffected by an ambient beads override"
}

test_local_handoff_refuses_beads_storage_under_any_ambient_backend
test_remote_outbox_staging_refuses_beads_storage_under_any_ambient_backend
test_receive_refuses_beads_storage_under_any_ambient_backend
test_markdown_home_is_not_refused_by_an_ambient_beads_override
