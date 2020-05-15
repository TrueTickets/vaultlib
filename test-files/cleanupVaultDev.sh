#!/usr/bin/env bash
# shellcheck disable=SC2155

# Where are we?
declare -r SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}"  )" >/dev/null 2>&1 && pwd  )"
declare -r VAULT_PID="${SCRIPT_DIR}/vault.pid"

# Shutdown the test vault instance
kill "$(cat "${VAULT_PID}")"

rm "${VAULT_PID}"
unset VAULT_TOKEN
