#!/usr/bin/env bash
# shellcheck disable=SC2155

declare -r VAULT_ADDR=http://localhost:8200
declare -r VAULT_TOKEN=my-dev-root-vault-token
declare -r VAULT_VERSION=${1:-1.4.1}

# Where are we?
declare -r SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}"  )" >/dev/null 2>&1 && pwd  )"
declare -r VAULT_BIN_DIR="${SCRIPT_DIR}/vault"
declare -r VAULT_BIN="${VAULT_BIN_DIR}/vault${VAULT_VERSION}"
declare -r VAULT_LOG_DIR="${SCRIPT_DIR}/logs"
declare -r VAULT_LOG="${VAULT_LOG_DIR}/vault${VAULT_VERSION}.log"
declare -r VAULT_PID="${SCRIPT_DIR}/vault.pid"

# Check for leftover processes from previous run
if [[ -f "${VAULT_PID}" ]]; then
  echo "There is a pid file present from a previous run. Aborting!"
  exit 1
fi

case "$(uname -s)" in
  Darwin*)
    OS="darwin_amd64"
    ;;
  MINGW64*)
    OS="windows_amd64"
    ;;
  *)
    OS="linux_amd64"
    ;;
esac

# Create dirs if they doesn't exist
[[ ! -d $VAULT_BIN_DIR ]] && mkdir "${VAULT_BIN_DIR}"
[[ ! -d $VAULT_LOG_DIR ]] && mkdir "${VAULT_LOG_DIR}"

# Download Vault if we don't have this version
if [[ ! -x $VAULT_BIN ]]; then
    curl -O "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_${OS}.zip"
    unzip "vault_${VAULT_VERSION}_${OS}.zip"
    mv vault "${VAULT_BIN}"
    rm "vault_${VAULT_VERSION}_${OS}.zip"
fi

# Export vars that we need
export VAULT_ADDR VAULT_TOKEN

${VAULT_BIN} server -dev -dev-root-token-id ${VAULT_TOKEN} > "${VAULT_LOG}" &
# Save the pid so we can stop it later
echo $! > "${VAULT_PID}"
# Wait for vault server to be ready
sleep 5

{
  # Create token
  ${VAULT_BIN} token create -period=10s -id="my-renewable-token"

  # Create KVs
  ${VAULT_BIN} secrets enable -path=kv_v1/path/ kv
  ${VAULT_BIN} secrets enable -path=kv_v2/path/ kv
  ${VAULT_BIN} kv enable-versioning kv_v2/path/

  # Create secrets
  ${VAULT_BIN} kv put kv_v1/path/my-secret my-v1-secret=my-v1-secret-value
  ${VAULT_BIN} kv put kv_v2/path/my-secret my-first-secret=my-first-secret-value my-second-secret=my-second-secret-value
  ${VAULT_BIN} kv put kv_v2/path/json-secret @"${SCRIPT_DIR}/secret.json"
  ${VAULT_BIN} kv put kv_v1/path/json-secret @"${SCRIPT_DIR}/secret.json"

  # Create policies
  ${VAULT_BIN} policy write VaultDevAdmin "${SCRIPT_DIR}/VaultPolicy.hcl"
  ${VAULT_BIN} policy write VaultNoKV "${SCRIPT_DIR}/NoKVVaultPolicy.hcl"
  # Create AppRoles
  ${VAULT_BIN} auth enable approle
  ${VAULT_BIN} write auth/approle/role/my-role policies=VaultDevAdmin token_num_uses=100 token_ttl=10s token_max_ttl=300m secret_id_num_uses=40
  ${VAULT_BIN} write auth/approle/role/no-kv policies=VaultNoKV token_num_uses=2 token_ttl=30m token_max_ttl=300m secret_id_num_uses=40
} >> "${VAULT_LOG}"
