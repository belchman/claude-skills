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
#                              line in source order. Empty output + exit 0
#                              when: spec file is missing, lane heading not
#                              found, or the H3 is not followed by a ```paths
#                              fence (malformed). The orchestrator decides
#                              whether empty = "skip this lane" or "spec is
#                              broken" via context; the lib stays uniform.
#   route_findings <findings> <spec>
#                              For each non-empty line of <findings>, find the
#                              first path-looking token in it and classify
#                              against the lanes parsed from <spec>. Prints
#                              one line per finding as `<lane>\t<finding>`.
#                              Findings whose path matches no lane (or has no
#                              extractable path) are tagged with the literal
#                              lane name `<unmapped>`. Fails loud (exit 1,
#                              stderr message naming the path) if any path
#                              appears in two or more lanes inside the spec.

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
  awk -v want="$lane" '
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
    in_paths { print }
  ' "$spec"
}

route_findings() {
  local findings="$1" spec="$2"
  [[ -f "$findings" ]] || return 0
  [[ -f "$spec" ]] || return 0

  # Step 1: build path -> lane map. Fail loud if any path appears in 2+ lanes.
  declare -A path_to_lane=()
  local lane path lanes
  lanes=$(awk '/^### / { line=substr($0,5); sub(/[[:space:]]+$/,"",line); print line }' "$spec")
  while IFS= read -r lane; do
    [[ -z "$lane" ]] && continue
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if [[ -n "${path_to_lane[$path]:-}" && "${path_to_lane[$path]}" != "$lane" ]]; then
        echo "route_findings: path '$path' appears in multiple lanes ('${path_to_lane[$path]}' and '$lane')" >&2
        return 1
      fi
      path_to_lane[$path]="$lane"
    done < <(allowlist_for "$spec" "$lane")
  done <<< "$lanes"

  # Step 2: classify each non-empty line of the findings file.
  # The first path-looking token (contains `/`, ends in `.ext`, breaks on whitespace/colon/backtick)
  # is the classification key. Lines with no extractable path → <unmapped>.
  local line found_path matched_lane
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    found_path=$(grep -oE '[^[:space:]:`]+/[^[:space:]:`]+\.[a-zA-Z0-9]+' <<< "$line" | head -1)
    if [[ -n "$found_path" && -n "${path_to_lane[$found_path]:-}" ]]; then
      matched_lane="${path_to_lane[$found_path]}"
    else
      matched_lane="<unmapped>"
    fi
    printf '%s\t%s\n' "$matched_lane" "$line"
  done < "$findings"
}
