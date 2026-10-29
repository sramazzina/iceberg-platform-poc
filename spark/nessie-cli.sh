#!/usr/bin/env bash
# Nessie CLI (installed as /usr/local/bin/nessie). Without -u/--uri it connects to the Nessie
# service of the lab. The up-to-date check is off: the lab does not call the internet.
set -euo pipefail

uri=(-u http://nessie:19120/api/v2)
for arg in "$@"; do
  case $arg in
    -u* | --uri | --uri=*) uri=() ;;
  esac
done

exec java -jar /opt/nessie-cli/nessie-cli.jar --no-up-to-date-check "${uri[@]}" "$@"
