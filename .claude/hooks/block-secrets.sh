#!/usr/bin/env bash
# PreToolUse hook for Write and Edit. Blocks writes that contain obvious secrets
# or target known-sensitive filenames. Exits 2 to block; writes diagnostics to stderr.
set -euo pipefail

input="$(cat)"

# Extract file_path and content from the tool_input JSON. Require jq — a sed
# fallback cannot safely parse JSON with embedded quotes/newlines, and silently
# failing open in a *secret blocker* defeats its purpose.
if ! command -v jq >/dev/null 2>&1; then
  echo "block-secrets: jq is required (install: brew install jq / apt install jq)" >&2
  exit 2
fi
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
content="$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // empty')"

violations=()

case "$file_path" in
  *.env|*.env.*|*.pem|*.key|*/id_rsa|*/id_ed25519|*credentials*.json|*service-account*.json)
    violations+=("sensitive filename: $file_path")
    ;;
esac

check() {
  local pattern="$1" label="$2"
  if printf '%s' "$content" | grep -Eq -- "$pattern"; then
    violations+=("$label")
  fi
}

check 'AKIA[0-9A-Z]{16}'                                              "AWS access key"
check 'aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}' "AWS secret key"
check '-----BEGIN (RSA |OPENSSH |EC |DSA |PGP )?PRIVATE KEY-----'     "private key block"
check 'xox[baprs]-[A-Za-z0-9-]{10,}'                                  "Slack token"
check 'ghp_[A-Za-z0-9]{36}'                                           "GitHub PAT (classic)"
check 'github_pat_[A-Za-z0-9_]{82}'                                   "GitHub PAT (fine-grained)"
check 'gho_[A-Za-z0-9]{36}'                                           "GitHub OAuth token"
check 'glpat-[A-Za-z0-9_-]{20}'                                       "GitLab PAT"
check 'AIza[0-9A-Za-z_-]{35}'                                         "Google API key"
check 'sk_(live|test)_[A-Za-z0-9]{24,}'                               "Stripe secret key"
check 'rk_(live|test)_[A-Za-z0-9]{24,}'                               "Stripe restricted key"
check 'sk-ant-(api|admin)[0-9]{2}-[A-Za-z0-9_-]{80,}'                 "Anthropic API key"
check 'sk-[A-Za-z0-9]{32,}'                                           "OpenAI-style API key"
check 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}' "JWT"

if [ ${#violations[@]} -gt 0 ]; then
  {
    echo "block-secrets: refusing write. Found:"
    printf '  - %s\n' "${violations[@]}"
    echo
    echo "If this is a placeholder or test fixture, scrub the value or move the file out of the repo."
  } >&2
  exit 2
fi

exit 0
