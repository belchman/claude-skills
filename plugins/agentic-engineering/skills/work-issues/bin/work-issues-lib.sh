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
