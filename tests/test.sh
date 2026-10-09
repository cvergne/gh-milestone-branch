#!/usr/bin/env bash
# Tests for gh-milestone-branch, using a stub `gh` that replays fixed JSON.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Stub gh: records its args, applies --jq to $STUB_JSON using the real jq.
mkdir "$work_dir/bin"
cat > "$work_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_ARGS_FILE"
filter=""
while [ $# -gt 0 ]; do
  [ "$1" = "--jq" ] && filter="$2"
  shift
done
printf '%s' "$STUB_JSON" | jq -r "$filter"
EOF
chmod +x "$work_dir/bin/gh"

export PATH="$work_dir/bin:$PATH"
export STUB_ARGS_FILE="$work_dir/args"
cmd="$root/gh-milestone-branch"
failures=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    failures=$((failures + 1))
  fi
}

# --- branch ---

# Stack A<-B<-C on main, plus independent D on main.
export STUB_JSON='[
  {"headRefName":"A","baseRefName":"main"},
  {"headRefName":"B","baseRefName":"A"},
  {"headRefName":"C","baseRefName":"B"},
  {"headRefName":"D","baseRefName":"main"}
]'
check "branch returns stack tips" "C
D" "$("$cmd" branch "v1" 2>&1)"

check "branch passes milestone in search" 'milestone:"v1"' "$(grep '^milestone:' "$STUB_ARGS_FILE")"

"$cmd" branch 'a"b' > /dev/null 2>&1
check "branch escapes quotes in milestone" 'milestone:"a\"b"' "$(grep '^milestone:' "$STUB_ARGS_FILE")"

STUB_JSON='[]'
check "branch on empty milestone gives no output" "" "$("$cmd" branch "v2" 2>&1)"

"$cmd" > /dev/null 2>&1
check "no subcommand exits 2" "2" "$?"

"$cmd" branch > /dev/null 2>&1
check "branch without milestone exits 2" "2" "$?"

"$cmd" bogus v1 > /dev/null 2>&1
check "unknown subcommand exits 2" "2" "$?"

"$cmd" switch v1 > /dev/null 2>&1
check "switch without new branch exits 2" "2" "$?"

# --- switch ---

# Throwaway repo with a bare origin; $1 is the pre-existing local branch
# ("local"), or "remote-only" to leave the tip only on origin.
setup_repo() {
  local mode="$1"
  rm -rf "$work_dir/origin.git" "$work_dir/repo"
  git init -q --bare "$work_dir/origin.git"
  git init -q -b main "$work_dir/repo"
  cd "$work_dir/repo" || exit 1
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
  git remote add origin "$work_dir/origin.git"
  git commit -q --allow-empty -m init
  git switch -q -c tip
  git commit -q --allow-empty -m tip
  git push -q origin main tip
  git switch -q main
  if [ "$mode" = "remote-only" ]; then
    git branch -q -D tip
    git fetch -q origin
  fi
}

STUB_JSON='[{"headRefName":"tip","baseRefName":"main"}]'

setup_repo local
"$cmd" switch v1 feature > /dev/null 2>&1
check "switch from local tip: exit 0" "0" "$?"
check "switch from local tip: on new branch" "feature" "$(git branch --show-current)"
check "switch from local tip: starts at tip" "$(git rev-parse tip)" "$(git rev-parse feature)"

setup_repo remote-only
"$cmd" switch v1 feature > /dev/null 2>&1
check "switch from origin tip: exit 0" "0" "$?"
check "switch from origin tip: starts at origin/tip" "$(git rev-parse origin/tip)" "$(git rev-parse feature)"

setup_repo local
STUB_JSON='[{"headRefName":"tip","baseRefName":"main"},{"headRefName":"other","baseRefName":"main"}]'
out="$("$cmd" switch v1 feature 2>&1)"
check "switch with several tips: exit 1" "1" "$?"
check "switch with several tips: no branch created" "main" "$(git branch --show-current)"
case "$out" in
  *tip*other*|*other*tip*) check "switch with several tips: lists candidates" ok ok ;;
  *) check "switch with several tips: lists candidates" "tip and other listed" "$out" ;;
esac

STUB_JSON='[]'
"$cmd" switch v1 feature > /dev/null 2>&1
check "switch with no tip: exit 1" "1" "$?"

STUB_JSON='[{"headRefName":"gone","baseRefName":"main"}]'
"$cmd" switch v1 feature > /dev/null 2>&1
check "switch with missing tip branch: exit 1" "1" "$?"

exit "$failures"
