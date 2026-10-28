#!/usr/bin/env bash
# Fails when the repository holds a credential or an account-specific value.
# Scans tracked files and untracked files that are not git-ignored.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
for path in .env secrets; do
  if [[ -n $(git ls-files -- "$path") ]]; then
    echo "tracked file under $path"
    status=1
  fi
done

# AWS access key ids and real account ids in ARNs. 123456789012 is the fake test account.
matches=$(git ls-files -z -co --exclude-standard \
  | xargs -0 grep -nIE 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|arn:aws:[a-z0-9-]+::[0-9]{12}' 2>/dev/null \
  | grep -v '123456789012' || true)
if [[ -n $matches ]]; then
  echo "possible credential or account id:"
  echo "$matches"
  status=1
fi

if ((status == 0)); then echo "no secrets found"; fi
exit $status
