#!/usr/bin/env bash
# Shared helpers for work-issues wrappers (once.sh, loop.sh) and downstream
# orchestrators (e.g. feature-helpers.sh). Sourced, not executed.
#
# Functions:
#   strip_frontmatter <file>   Print file contents with leading YAML
#                              frontmatter (--- ... ---) removed. If the file
#                              has no leading ---, the whole file is printed.
#   list_issue_files <dir>     Print paths to issue files directly under <dir>,
#                              one per line, in LC_ALL=C sorted order (stable
#                              across runs and machines — keeps the prompt
#                              byte-identical for prompt-caching). Excludes
#                              sidecar suffixes (*.rubric.md, *.spec.md,
#                              *.research.md) and does not recurse into
#                              subdirectories. Missing dir → silent empty
#                              output (no find error on stderr).
#   allowlist_for <spec> <lane>
#                              Extract the file paths inside the ```paths
#                              fenced block under the H3 heading whose text
#                              equals <lane> in <spec>. Prints one path per
#                              line in source order, with leading/trailing
#                              whitespace trimmed and blank-after-trim lines
#                              dropped. Empty output + exit 0 when: spec file
#                              is missing, lane heading not found, or the H3
#                              is not followed by a ```paths fence (malformed
#                              — these three cases are intentionally
#                              indistinguishable; the orchestrator decides
#                              whether empty = "skip this lane" or "spec is
#                              broken" via context). FAILS LOUD (exit 1,
#                              stderr names the offending line) if any path
#                              contains a glob/wildcard char (`*`, `?`, `[`)
#                              — plan §C and ADR 0001 forbid globs in v1.
#   route_findings <findings> <spec>
#                              Requires bash 4+ (uses associative array).
#                              Refuses with exit 2 on bash 3.x. For each
#                              non-empty line of <findings>, extracts the
#                              FIRST path-looking token (greedy on
#                              path-safe chars, stops on whitespace/quote/
#                              paren/brace/backtick/comma/semicolon) and
#                              strips a trailing :N(:M)? line/column
#                              reference. Reads through to the last line
#                              even when <findings> has no trailing newline.
#                              Classifies the extracted path against the
#                              lanes parsed from <spec>. Prints one line per
#                              finding as `<lane>\t<finding>`. Findings whose
#                              path matches no lane (or has no extractable
#                              path) are tagged with the literal lane name
#                              `<unmapped>`. Fails loud (exit 1, stderr names
#                              the path) if any path appears in two or more
#                              lanes inside the spec, or propagates the exit
#                              code if allowlist_for rejects a lane (e.g.
#                              globs).

strip_frontmatter() {
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { in_fm=0; next }
    in_fm { next }
    { print }
  ' "$1"
}

list_issue_files() {
  [[ -d "$1" ]] || return 0
  find "$1" -maxdepth 1 -type f -name '*.md' \
    -not -name '*.rubric.md' \
    -not -name '*.spec.md' \
    -not -name '*.research.md' \
    | LC_ALL=C sort
}

allowlist_for() {
  local spec="$1" lane="$2"
  [[ -f "$spec" ]] || return 0
  local paths
  paths=$(awk -v want="$lane" '
    /^### / {
      # H3 heading: capture text after "### " as the lane name
      cur = substr($0, 5)
      sub(/[[:space:]]+$/, "", cur)
      in_lane = (cur == want) ? 1 : 0
      in_paths = 0
      next
    }
    in_lane && /^```paths[[:space:]]*$/ { in_paths = 1; next }
    in_paths && /^```[[:space:]]*$/ { exit }
    in_paths {
      # Trim leading/trailing whitespace; skip blank lines.
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      if (length($0)) print
    }
  ' "$spec")
  # Reject globs / wildcards per plan §C ("No globs in v1") + ADR 0001.
  local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    case "$p" in
      *'*'*|*'?'*|*'['*)
        echo "allowlist_for: glob/wildcard not allowed in v1 paths block: '$p'" >&2
        return 1
        ;;
    esac
  done <<< "$paths"
  [[ -n "$paths" ]] && printf '%s\n' "$paths"
  return 0
}

route_findings() {
  # Bash 4+ required for associative arrays. macOS /bin/bash is 3.2 — fail loud.
  if (( BASH_VERSINFO[0] < 4 )); then
    echo "route_findings: requires bash 4+ (got $BASH_VERSION). Install via 'brew install bash' and run under /usr/bin/env bash." >&2
    return 2
  fi

  local findings="$1" spec="$2"
  [[ -f "$findings" ]] || return 0
  [[ -f "$spec" ]] || return 0

  # Step 1: build path -> lane map. Fail loud if any path appears in 2+ lanes,
  # or if allowlist_for itself fails (e.g. spec contains globs).
  declare -A path_to_lane=()
  local lane path lanes
  lanes=$(awk '/^### / { line=substr($0,5); sub(/[[:space:]]+$/,"",line); print line }' "$spec")
  local allowlist al_status
  while IFS= read -r lane; do
    [[ -z "$lane" ]] && continue
    # Capture both stdout and exit status of allowlist_for.
    allowlist=$(allowlist_for "$spec" "$lane")
    al_status=$?
    if (( al_status != 0 )); then
      echo "route_findings: allowlist_for failed for lane '$lane' (exit $al_status)" >&2
      return "$al_status"
    fi
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if [[ -n "${path_to_lane[$path]:-}" && "${path_to_lane[$path]}" != "$lane" ]]; then
        echo "route_findings: path '$path' appears in multiple lanes ('${path_to_lane[$path]}' and '$lane')" >&2
        return 1
      fi
      path_to_lane[$path]="$lane"
    done <<< "$allowlist"
  done <<< "$lanes"

  # Step 2: classify each non-empty line of the findings file.
  # The first path-looking token (contains `/`, breaks on whitespace, backtick,
  # quote, comma, paren, brace) is extracted, then a trailing :line(:col)
  # suffix is stripped. Net effect: src/api.ts:42  → src/api.ts;
  # src/api.ts-bak:5 → src/api.ts-bak (full filename, no false-match on api.ts).
  # The `|| [[ -n "$line" ]]` keeps the last line if findings has no trailing \n.
  local line found_path matched_lane
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    found_path=$(grep -oE "[^[:space:]\`,;()\"'{}]+/[^[:space:]\`,;()\"'{}]+" <<< "$line" | head -1)
    # Strip a trailing :N(:M)? line/column reference if present.
    found_path="${found_path%%:[0-9]*}"
    if [[ -n "$found_path" && -n "${path_to_lane[$found_path]:-}" ]]; then
      matched_lane="${path_to_lane[$found_path]}"
    else
      matched_lane="<unmapped>"
    fi
    printf '%s\t%s\n' "$matched_lane" "$line"
  done < "$findings"
}
