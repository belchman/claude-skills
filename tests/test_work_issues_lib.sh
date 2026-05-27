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

# ---- behavior: allowlist_for extracts paths from named lane ---------------

test_allowlist_for_happy_path() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec
  spec=$(mktemp)
  cat > "$spec" <<'EOF'
# Some feature — Spec

## File-by-file change list

### Backend

```paths
src/api/handlers/invoices.ts
src/services/invoice-reminder.ts
```

### Frontend

```paths
web/components/billing/ReminderCard.tsx
web/hooks/useInvoiceReminders.ts
```
EOF
  local got want
  got=$(allowlist_for "$spec" Backend)
  want=$'src/api/handlers/invoices.ts\nsrc/services/invoice-reminder.ts'
  rm -f "$spec"
  assert_eq "allowlist_for: extracts only named lane's paths in source order" "$want" "$got"
}

# ---- behavior: allowlist_for on a lane that's not in the spec -------------

test_allowlist_for_lane_not_found() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec err_log
  spec=$(mktemp); err_log=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend

```paths
src/a.ts
```
EOF
  local got err exit_code
  got=$(allowlist_for "$spec" Frontend 2>"$err_log"); exit_code=$?
  err=$(cat "$err_log")
  rm -f "$spec" "$err_log"
  assert_eq "allowlist_for: lane-not-found → empty stdout" "" "$got"
  assert_eq "allowlist_for: lane-not-found → empty stderr" "" "$err"
  assert_eq "allowlist_for: lane-not-found → exit 0" "0" "$exit_code"
}

# ---- behavior: allowlist_for on a missing spec file ------------------------

test_allowlist_for_missing_file() {
  # shellcheck disable=SC1090
  source "$lib"
  local got err err_log exit_code
  err_log=$(mktemp)
  got=$(allowlist_for /no/such/spec.md Backend 2>"$err_log"); exit_code=$?
  err=$(cat "$err_log")
  rm -f "$err_log"
  assert_eq "allowlist_for: missing file → empty stdout" "" "$got"
  assert_eq "allowlist_for: missing file → empty stderr" "" "$err"
  assert_eq "allowlist_for: missing file → exit 0" "0" "$exit_code"
}

# ---- behavior: allowlist_for on H3 heading with no following paths block ---
# Per AF-4: behavior pinned by test. Documented in lib header as "empty stdout + exit 0".

test_allowlist_for_malformed_no_paths_block() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec err_log
  spec=$(mktemp); err_log=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend

Some prose. No fenced paths block here.

### Frontend

```paths
web/a.tsx
```
EOF
  local got err exit_code
  got=$(allowlist_for "$spec" Backend 2>"$err_log"); exit_code=$?
  err=$(cat "$err_log")
  rm -f "$spec" "$err_log"
  assert_eq "allowlist_for: malformed (H3 without paths fence) → empty stdout" "" "$got"
  assert_eq "allowlist_for: malformed → empty stderr (consistent with lane-not-found)" "" "$err"
  assert_eq "allowlist_for: malformed → exit 0" "0" "$exit_code"
}

# ---- behavior: allowlist_for filters by lane (no cross-lane bleed) ---------

test_allowlist_for_no_cross_lane_bleed() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec
  spec=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/api.ts
src/svc.ts
```
### Frontend
```paths
web/c.tsx
web/d.tsx
```
EOF
  local got want
  got=$(allowlist_for "$spec" Frontend)
  want=$'web/c.tsx\nweb/d.tsx'
  rm -f "$spec"
  assert_eq "allowlist_for: requesting Frontend returns ONLY Frontend paths" "$want" "$got"
}

# ---- behavior: route_findings classifies each finding by lane allowlist ----

test_route_findings_happy_path() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec findings
  spec=$(mktemp); findings=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/api/handlers/invoices.ts
src/services/invoice-reminder.ts
```
### Frontend
```paths
web/components/ReminderCard.tsx
```
EOF
  cat > "$findings" <<'EOF'
1. src/api/handlers/invoices.ts:42 — missing auth check
2. web/components/ReminderCard.tsx:8 — no loading state
3. config/plans.yaml:5 — limit value should be 100, not 1000
EOF
  local got
  got=$(route_findings "$findings" "$spec")
  rm -f "$spec" "$findings"
  # Expect: one line per finding, tab-separated lane + full original line
  local expected
  expected=$'Backend\t1. src/api/handlers/invoices.ts:42 — missing auth check\nFrontend\t2. web/components/ReminderCard.tsx:8 — no loading state\n<unmapped>\t3. config/plans.yaml:5 — limit value should be 100, not 1000'
  assert_eq "route_findings: classifies each finding by lane (incl. <unmapped>)" "$expected" "$got"
}

# ---- behavior: route_findings on an empty findings file -------------------

test_route_findings_empty() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec findings err_log
  spec=$(mktemp); findings=$(mktemp); err_log=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/a.ts
```
EOF
  : > "$findings"  # truncate to empty
  local got err exit_code
  got=$(route_findings "$findings" "$spec" 2>"$err_log"); exit_code=$?
  err=$(cat "$err_log")
  rm -f "$spec" "$findings" "$err_log"
  assert_eq "route_findings: empty findings → empty stdout" "" "$got"
  assert_eq "route_findings: empty findings → empty stderr" "" "$err"
  assert_eq "route_findings: empty findings → exit 0" "0" "$exit_code"
}

# ---- behavior: route_findings fails loud on cross-lane duplicate paths ----

test_route_findings_fail_loud_on_duplicate() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec findings err_log
  spec=$(mktemp); findings=$(mktemp); err_log=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/shared.ts
```
### Frontend
```paths
src/shared.ts
```
EOF
  cat > "$findings" <<'EOF'
1. src/shared.ts:1 — something
EOF
  local got err exit_code
  got=$(route_findings "$findings" "$spec" 2>"$err_log"); exit_code=$?
  err=$(cat "$err_log")
  rm -f "$spec" "$findings" "$err_log"
  # Must exit non-zero
  if (( exit_code == 0 )); then
    echo "  FAIL  route_findings: duplicate path should exit non-zero (got exit 0)"
    fail_count=$((fail_count + 1))
  else
    echo "  PASS  route_findings: duplicate path exits non-zero (exit $exit_code)"
    pass_count=$((pass_count + 1))
  fi
  # Stderr must mention the duplicated path
  if [[ "$err" == *"src/shared.ts"* ]]; then
    echo "  PASS  route_findings: duplicate stderr names the duplicated path"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  route_findings: duplicate stderr should name 'src/shared.ts' (got: $err)"
    fail_count=$((fail_count + 1))
  fi
}

# ---- bug fixes from Round 3a adversarial review ----------------------------

# CRITICAL #1: bash 4+ guard — route_findings must refuse loudly on bash 3.x
# rather than dying with "declare: -A: invalid option" + unset-var cascade.
# We can't easily run a sub-bash 3 from here, so pin the GUARD's presence
# by inspection: the function body must reference BASH_VERSINFO.
test_route_findings_has_bash_version_guard() {
  if grep -q 'BASH_VERSINFO' "$lib"; then
    echo "  PASS  route_findings: bash version guard present in lib"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  route_findings: missing BASH_VERSINFO guard (will die ugly on bash 3.2)"
    fail_count=$((fail_count + 1))
  fi
}

# CRITICAL #2: last line of findings with no trailing newline must not drop.
test_route_findings_handles_missing_trailing_newline() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec findings
  spec=$(mktemp); findings=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/api.ts
```
EOF
  # printf with no trailing \n — common from `claude -p` capture or `gh` JSON pipes
  printf '1. src/api.ts:42 — last line no newline' > "$findings"
  local got
  got=$(route_findings "$findings" "$spec")
  rm -f "$spec" "$findings"
  local want=$'Backend\t1. src/api.ts:42 — last line no newline'
  assert_eq "route_findings: last line without trailing \\n is still classified" "$want" "$got"
}

# CRITICAL #3: allowlist_for must reject globs (plan §C: "No globs in v1").
test_allowlist_for_rejects_globs() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec err_log
  spec=$(mktemp); err_log=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/api/**/*.ts
src/svc.ts
```
EOF
  local got err exit_code
  got=$(allowlist_for "$spec" Backend 2>"$err_log"); exit_code=$?
  err=$(cat "$err_log")
  rm -f "$spec" "$err_log"
  if (( exit_code == 0 )); then
    echo "  FAIL  allowlist_for: glob should be rejected with non-zero exit (got 0)"
    fail_count=$((fail_count + 1))
  else
    echo "  PASS  allowlist_for: rejects glob with non-zero exit (exit $exit_code)"
    pass_count=$((pass_count + 1))
  fi
  if [[ "$err" == *"glob"* || "$err" == *"*"* ]]; then
    echo "  PASS  allowlist_for: stderr mentions glob/wildcard"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  allowlist_for: stderr should mention glob/wildcard (got: $err)"
    fail_count=$((fail_count + 1))
  fi
}

# CRITICAL #4: whitespace-padded paths must not silently mis-route.
# Resolution: allowlist_for trims, so the map key matches the trimmed lookup.
test_allowlist_for_trims_whitespace() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec
  spec=$(mktemp)
  # Use printf to embed real leading/trailing spaces (won't survive heredoc easily)
  {
    echo '### Backend'
    echo '```paths'
    echo '  src/leading.ts'
    echo 'src/trailing.ts  '
    echo '```'
  } > "$spec"
  local got want
  got=$(allowlist_for "$spec" Backend)
  want=$'src/leading.ts\nsrc/trailing.ts'
  rm -f "$spec"
  assert_eq "allowlist_for: trims leading/trailing whitespace from paths" "$want" "$got"
}

# IMPORTANT (config #5 + coverage #3): regex must not classify adjacent
# filename src/api.ts-bak as src/api.ts (extension-boundary bug).
test_route_findings_does_not_match_adjacent_filename() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec findings
  spec=$(mktemp); findings=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/api.ts
```
EOF
  cat > "$findings" <<'EOF'
1. src/api.ts-bak:5 — different file (backup variant)
EOF
  local got
  got=$(route_findings "$findings" "$spec")
  rm -f "$spec" "$findings"
  # The finding is about a different file (src/api.ts-bak), should be unmapped, NOT Backend
  local want=$'<unmapped>\t1. src/api.ts-bak:5 — different file (backup variant)'
  assert_eq "route_findings: src/api.ts-bak NOT misclassified as src/api.ts" "$want" "$got"
}

# CRITICAL (Round 3b adversarial review): brace expansion {foo,bar} must be
# rejected as a glob — SKILL.md anti-patterns forbids it; impl must enforce.
test_allowlist_for_rejects_brace_expansion() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec err_log
  spec=$(mktemp); err_log=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/{api,svc}/foo.ts
```
EOF
  local exit_code err
  allowlist_for "$spec" Backend >/dev/null 2>"$err_log"; exit_code=$?
  err=$(cat "$err_log")
  rm -f "$spec" "$err_log"
  if (( exit_code == 0 )); then
    echo "  FAIL  allowlist_for: brace expansion should be rejected (got exit 0)"
    fail_count=$((fail_count + 1))
  else
    echo "  PASS  allowlist_for: rejects brace expansion (exit $exit_code)"
    pass_count=$((pass_count + 1))
  fi
}

# IMPORTANT (config #5 propagation): route_findings must propagate allowlist_for's
# non-zero exit (e.g. when allowlist contains globs and gets rejected).
test_route_findings_propagates_allowlist_for_failure() {
  # shellcheck disable=SC1090
  source "$lib"
  local spec findings err_log
  spec=$(mktemp); findings=$(mktemp); err_log=$(mktemp)
  cat > "$spec" <<'EOF'
### Backend
```paths
src/**/*.ts
```
EOF
  cat > "$findings" <<'EOF'
1. src/foo.ts:1 — bug
EOF
  local exit_code err
  route_findings "$findings" "$spec" >/dev/null 2>"$err_log"; exit_code=$?
  err=$(cat "$err_log")
  rm -f "$spec" "$findings" "$err_log"
  if (( exit_code == 0 )); then
    echo "  FAIL  route_findings: should propagate non-zero from allowlist_for on glob spec"
    fail_count=$((fail_count + 1))
  else
    echo "  PASS  route_findings: propagates non-zero exit from allowlist_for (exit $exit_code)"
    pass_count=$((pass_count + 1))
  fi
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
test_allowlist_for_happy_path
test_allowlist_for_lane_not_found
test_allowlist_for_missing_file
test_allowlist_for_malformed_no_paths_block
test_allowlist_for_no_cross_lane_bleed
test_route_findings_happy_path
test_route_findings_empty
test_route_findings_fail_loud_on_duplicate
test_route_findings_has_bash_version_guard
test_route_findings_handles_missing_trailing_newline
test_allowlist_for_rejects_globs
test_allowlist_for_trims_whitespace
test_route_findings_does_not_match_adjacent_filename
test_allowlist_for_rejects_brace_expansion
test_route_findings_propagates_allowlist_for_failure

echo ""
echo "Results: $pass_count passed, $fail_count failed"
[[ $fail_count -eq 0 ]]
