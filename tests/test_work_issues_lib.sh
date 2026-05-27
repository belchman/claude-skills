#!/usr/bin/env bash
# Tests for work-issues/bin/work-issues-lib.sh.
# Run directly: bash tests/test_work_issues_lib.sh
# Exit code 0 = all tests pass; non-zero = at least one failure.

set -u  # -e is too aggressive — we want to count failures, not exit on first

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$repo_root/plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh"

pass_count=0
fail_count=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS  $name"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  $name"
    echo "    expected: $(printf '%q' "$expected")"
    echo "    actual:   $(printf '%q' "$actual")"
    fail_count=$((fail_count + 1))
  fi
}

# ---- behavior: strip_frontmatter removes YAML frontmatter -------------------

test_strip_frontmatter_removes_yaml() {
  # shellcheck disable=SC1090
  source "$lib"
  local fixture
  fixture=$(mktemp)
  cat > "$fixture" <<'EOF'
---
name: example
description: a skill
---
This is the body.
Second line.
EOF
  local got
  got=$(strip_frontmatter "$fixture")
  rm -f "$fixture"
  local want=$'This is the body.\nSecond line.'
  assert_eq "strip_frontmatter removes YAML frontmatter" "$want" "$got"
}

# ---- behavior: list_issue_files excludes sidecar suffixes ------------------

test_list_issue_files_excludes_sidecars() {
  # shellcheck disable=SC1090
  source "$lib"
  local dir
  dir=$(mktemp -d)
  # Issue files we WANT included:
  touch "$dir/001-foo.md"
  touch "$dir/042-bar-baz.md"
  # Sidecar files we want EXCLUDED:
  touch "$dir/042-bar-baz.rubric.md"
  touch "$dir/042-bar-baz.spec.md"
  touch "$dir/042-bar-baz.research.md"
  # Subdir should NOT be recursed into:
  mkdir "$dir/research"
  touch "$dir/research/042-extra.md"

  # Sort to make comparison stable
  local got
  got=$(list_issue_files "$dir" | sort)
  rm -rf "$dir"

  local want
  want=$(printf "%s\n%s" "$dir/001-foo.md" "$dir/042-bar-baz.md" | sort)
  assert_eq "list_issue_files excludes sidecars and recursion" "$want" "$got"
}

# ---- behavior: strip_frontmatter is a passthrough when no frontmatter ------

test_strip_frontmatter_passthrough_no_frontmatter() {
  # shellcheck disable=SC1090
  source "$lib"
  local fixture
  fixture=$(mktemp)
  cat > "$fixture" <<'EOF'
Just body, no frontmatter.
Second line.
EOF
  local got
  got=$(strip_frontmatter "$fixture")
  rm -f "$fixture"
  local want=$'Just body, no frontmatter.\nSecond line.'
  assert_eq "strip_frontmatter passthrough when no frontmatter" "$want" "$got"
}

# ---- behavior: list_issue_files on a missing dir is empty + silent ---------

test_list_issue_files_missing_dir_is_empty() {
  # shellcheck disable=SC1090
  source "$lib"
  local got err_log
  err_log=$(mktemp)
  got=$(list_issue_files /no/such/dir 2>"$err_log")
  local err
  err=$(cat "$err_log")
  rm -f "$err_log"
  assert_eq "list_issue_files missing dir: empty stdout" "" "$got"
  assert_eq "list_issue_files missing dir: empty stderr (no diagnostic leak)" "" "$err"
}

# ---- behavior: list_issue_files output is sorted ---------------------------

test_list_issue_files_sorted_numerically() {
  # shellcheck disable=SC1090
  source "$lib"
  local dir
  dir=$(mktemp -d)
  # Touch in non-sorted order so any naive readdir order would differ from sorted
  touch "$dir/100-zzz.md"
  touch "$dir/002-bbb.md"
  touch "$dir/050-ddd.md"
  touch "$dir/001-aaa.md"

  local got want
  got=$(list_issue_files "$dir")
  want=$(printf "%s\n%s\n%s\n%s" \
    "$dir/001-aaa.md" "$dir/002-bbb.md" "$dir/050-ddd.md" "$dir/100-zzz.md")
  rm -rf "$dir"
  assert_eq "list_issue_files is sorted (stable order for the prompt)" "$want" "$got"
}

# ---- run --------------------------------------------------------------------

if [[ ! -f "$lib" ]]; then
  echo "  SETUP FAIL  lib not found at: $lib"
  fail_count=$((fail_count + 1))
fi

test_strip_frontmatter_removes_yaml
test_strip_frontmatter_passthrough_no_frontmatter
test_list_issue_files_excludes_sidecars
test_list_issue_files_missing_dir_is_empty
test_list_issue_files_sorted_numerically

echo ""
echo "Results: $pass_count passed, $fail_count failed"
[[ $fail_count -eq 0 ]]
