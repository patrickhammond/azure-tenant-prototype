#!/usr/bin/env bash
#
# Platform bootstrap — the one-time, hand-run step that creates what OpenTofu cannot create for
# itself. See ../README.md for the procedure and openspec/changes/platform-bootstrap-remote-state/
# design.md for why each piece is here.
#
# It creates exactly four things and stops:
#
#   1. the resource group
#   2. the state storage account   (shared-key access OFF — Entra only)
#   3. the platform state container
#   4. the Key Vault + RSA key that enforced state encryption needs
#
# Everything else — the remaining state containers, the delete lock, the management-group tree —
# is OpenTofu's job. Re-running this script is a no-op.

set -euo pipefail

# --------------------------------------------------------------------------------------------
# Defaults and arguments
# --------------------------------------------------------------------------------------------

LOCATION="eastus"
LOCATION_SHORT="eus"
SUBSCRIPTION_ID=""
RESOURCE_GROUP_OVERRIDE=""
STORAGE_ACCOUNT=""
KEY_VAULT=""
KEY_NAME="tofu-state-kek"
PLATFORM_CONTAINER="tfstate-platform"
SOFT_DELETE_DAYS=30
VAULT_RETENTION_DAYS=90
TAGS=("purpose=tofu-state" "managed-by=platform-bootstrap")

usage() {
  cat <<'USAGE'
Usage: bootstrap.sh --subscription <sub-platform id> [options]

Required:
  --subscription <guid>     The sub-platform subscription to bootstrap into.

Options:
  --location <region>       Azure region (default: eastus).
  --resource-group <name>   Target a different group than rg-platform-tfstate-<region>.
                            The platform's own group follows the naming convention and needs no
                            override; this exists for throwaway runs against a scratch group, where
                            bootstrapping into the real one would be wrong.
  --storage-account <name>  Reuse a specific state account instead of discovering or generating one.
  --key-vault <name>        Reuse a specific vault instead of discovering or generating one.
  --help                    Show this message.

Prerequisites (see ../README.md):
  * az CLI, signed in as a human identity (az login).
  * Owner on the target subscription — the script creates role assignments.
  * Management Group Contributor at the Tenant Root Group is needed for the OpenTofu apply that
    follows, not for this script.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)    SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --location)        LOCATION="${2:-}"; shift 2 ;;
    --resource-group)  RESOURCE_GROUP_OVERRIDE="${2:-}"; shift 2 ;;
    --storage-account) STORAGE_ACCOUNT="${2:-}"; shift 2 ;;
    --key-vault)       KEY_VAULT="${2:-}"; shift 2 ;;
    --help|-h)         usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$SUBSCRIPTION_ID" ]] || { echo "ERROR: --subscription is required." >&2; usage >&2; exit 2; }

RESOURCE_GROUP="${RESOURCE_GROUP_OVERRIDE:-rg-platform-tfstate-${LOCATION_SHORT}}"

created=()
skipped=()

note_created() { created+=("$1"); echo "  created  $1"; }
note_skipped() { skipped+=("$1"); echo "  exists   $1"; }
step()         { echo; echo "==> $1"; }

# Count non-empty lines. Avoids `mapfile`, which is bash 4+ and absent from the bash 3.2 that
# still ships with macOS — this script has to run on whatever a reader has.
count_lines() { [[ -z "${1//[[:space:]]/}" ]] && echo 0 || printf '%s\n' "$1" | grep -c . ; }

command -v az >/dev/null || { echo "ERROR: az CLI not found." >&2; exit 1; }

# --------------------------------------------------------------------------------------------
# Identity and preflight
# --------------------------------------------------------------------------------------------

step "Preflight"

if ! az account show >/dev/null 2>&1; then
  echo "ERROR: not signed in. Run 'az login' first." >&2
  exit 1
fi

TENANT_ID="$(az account show --subscription "$SUBSCRIPTION_ID" --query tenantId -o tsv)"
OPERATOR_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"

if [[ -z "$OPERATOR_OID" ]]; then
  echo "ERROR: could not resolve the signed-in user's object ID." >&2
  echo "       This script must run as a human identity, not a service principal —" >&2
  echo "       it grants that identity the data-plane roles the rest of the run needs." >&2
  exit 1
fi

echo "  subscription  $SUBSCRIPTION_ID"
echo "  tenant        $TENANT_ID"
echo "  operator      $OPERATOR_OID"
echo "  location      $LOCATION"

# --------------------------------------------------------------------------------------------
# Resource provider registration
#
# A fresh subscription has almost nothing registered, and the failure mode is actively
# misleading: creating a storage account under an unregistered Microsoft.Storage returns
# "SubscriptionNotFound", pointing at the one thing that is definitely fine. Register up front.
#
# Registration is idempotent and takes seconds to a couple of minutes the first time.
# --------------------------------------------------------------------------------------------

step "Resource providers"

for ns in Microsoft.Storage Microsoft.KeyVault Microsoft.Management; do
  state="$(az provider show --namespace "$ns" --subscription "$SUBSCRIPTION_ID" \
    --query registrationState -o tsv 2>/dev/null || echo "Unknown")"

  if [[ "$state" == "Registered" ]]; then
    note_skipped "provider $ns"
  else
    az provider register --namespace "$ns" --subscription "$SUBSCRIPTION_ID" --wait
    note_created "provider $ns"
  fi
done

# --------------------------------------------------------------------------------------------
# 1. Resource group
# --------------------------------------------------------------------------------------------

step "Resource group: $RESOURCE_GROUP"

if az group show --name "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
  note_skipped "resource group $RESOURCE_GROUP"
else
  az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --tags "${TAGS[@]}" \
    --output none
  note_created "resource group $RESOURCE_GROUP"
fi

# --------------------------------------------------------------------------------------------
# 2. Storage account
#
# Discovery before generation is what makes re-runs a no-op: a random suffix that regenerated on
# every run would create a second account each time.
# --------------------------------------------------------------------------------------------

step "Storage account"

if [[ -z "$STORAGE_ACCOUNT" ]]; then
  found="$(az storage account list \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?tags.purpose=='tofu-state'].name" -o tsv 2>/dev/null || true)"
  case "$(count_lines "$found")" in
    0) STORAGE_ACCOUNT="stplatformtfstate$(openssl rand -hex 3)" ;;
    1) STORAGE_ACCOUNT="$found" ;;
    *) echo "ERROR: multiple tofu-state accounts in $RESOURCE_GROUP:" >&2
       echo "$found" >&2
       echo "       Pass --storage-account to say which one to use." >&2
       exit 1 ;;
  esac
fi

if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
     --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
  note_skipped "storage account $STORAGE_ACCOUNT"
else
  # --allow-shared-key-access false is the P3 control: with it off, account keys and the account
  # and service SAS signed by them stop working entirely, for everyone, including us.
  az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-shared-key-access false \
    --allow-blob-public-access false \
    --public-network-access Enabled \
    --tags "${TAGS[@]}" \
    --output none
  note_created "storage account $STORAGE_ACCOUNT"
fi

# --------------------------------------------------------------------------------------------
# 3. Blob durability — versioning and soft delete
#
# Applied unconditionally: these are idempotent property writes, and re-running is how a partially
# configured account gets repaired.
# --------------------------------------------------------------------------------------------

step "Blob durability"

az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days "$SOFT_DELETE_DAYS" \
  --enable-container-delete-retention true \
  --container-delete-retention-days "$SOFT_DELETE_DAYS" \
  --output none

echo "  set      versioning on, blob and container soft delete ${SOFT_DELETE_DAYS}d"

# --------------------------------------------------------------------------------------------
# 4. Key Vault
# --------------------------------------------------------------------------------------------

step "Key Vault"

if [[ -z "$KEY_VAULT" ]]; then
  found_kv="$(az keyvault list \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?tags.purpose=='tofu-state'].name" -o tsv 2>/dev/null || true)"
  case "$(count_lines "$found_kv")" in
    0) KEY_VAULT="kv-plat-tfstate-$(openssl rand -hex 3)" ;;
    1) KEY_VAULT="$found_kv" ;;
    *) echo "ERROR: multiple tofu-state vaults in $RESOURCE_GROUP:" >&2
       echo "$found_kv" >&2
       echo "       Pass --key-vault to say which one to use." >&2
       exit 1 ;;
  esac
fi

if az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" \
     --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
  note_skipped "key vault $KEY_VAULT"
else
  # RBAC authorization, not legacy access policies (D2). Purge protection is irreversible once on,
  # which is the point: destroying this key makes every state file permanently unreadable.
  az keyvault create \
    --name "$KEY_VAULT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --sku standard \
    --enable-rbac-authorization true \
    --enable-purge-protection true \
    --retention-days "$VAULT_RETENTION_DAYS" \
    --tags "${TAGS[@]}" \
    --output none
  note_created "key vault $KEY_VAULT (purge protection ON — irreversible)"
fi

VAULT_URI="$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID" --query properties.vaultUri -o tsv)"

# --------------------------------------------------------------------------------------------
# 5. Data-plane role assignments — BEFORE any container or key operation
#
# Creating an RBAC-model resource grants the creator control-plane rights only. Owner on the
# subscription does NOT confer blob data access or Key Vault data access. Without these two
# assignments the container and key steps below fail with a 403 that reads like a bug in the
# script. This ordering is deliberate; do not move it after the data-plane steps.
# --------------------------------------------------------------------------------------------

step "Data-plane role assignments"

STORAGE_ID="$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID" --query id -o tsv)"
VAULT_ID="$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID" --query id -o tsv)"

assign_role() {
  local role="$1" scope="$2"
  local existing
  existing="$(az role assignment list \
    --assignee "$OPERATOR_OID" \
    --role "$role" \
    --scope "$scope" \
    --query "length(@)" -o tsv 2>/dev/null || echo 0)"

  if [[ "$existing" != "0" ]]; then
    note_skipped "role '$role'"
    return
  fi

  az role assignment create \
    --assignee-object-id "$OPERATOR_OID" \
    --assignee-principal-type User \
    --role "$role" \
    --scope "$scope" \
    --output none
  note_created "role '$role'"
}

# Storage Blob Data Contributor: create containers and read/write state blobs.
assign_role "Storage Blob Data Contributor" "$STORAGE_ID"
# Key Vault Crypto Officer: create the key. Running OpenTofu later needs only Crypto User.
assign_role "Key Vault Crypto Officer" "$VAULT_ID"

# Role assignments are eventually consistent. Poll rather than sleeping a guessed interval.
step "Waiting for role propagation"

wait_for() {
  local description="$1"; shift
  local attempt
  for attempt in $(seq 1 30); do
    if "$@" >/dev/null 2>&1; then
      echo "  ready    $description (attempt $attempt)"
      return 0
    fi
    sleep 10
  done
  echo "ERROR: $description did not become available within 5 minutes." >&2
  echo "       Role assignments were created; re-running the script usually succeeds." >&2
  return 1
}

wait_for "blob data access" \
  az storage container list --account-name "$STORAGE_ACCOUNT" --auth-mode login --subscription "$SUBSCRIPTION_ID"
wait_for "key vault data access" \
  az keyvault key list --vault-name "$KEY_VAULT"

# --------------------------------------------------------------------------------------------
# 6. Platform state container
# --------------------------------------------------------------------------------------------

step "State container: $PLATFORM_CONTAINER"

if [[ "$(az storage container exists --name "$PLATFORM_CONTAINER" \
          --account-name "$STORAGE_ACCOUNT" --auth-mode login \
          --subscription "$SUBSCRIPTION_ID" --query exists -o tsv)" == "true" ]]; then
  note_skipped "container $PLATFORM_CONTAINER"
else
  az storage container create \
    --name "$PLATFORM_CONTAINER" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
  note_created "container $PLATFORM_CONTAINER"
fi

# --------------------------------------------------------------------------------------------
# 7. Key-encryption key
#
# RSA in a standard vault, NOT a symmetric AES key: azure_vault supports symmetric keys only in
# Managed HSM, whose monthly floor breaches P1 by three orders of magnitude.
# --------------------------------------------------------------------------------------------

step "Key-encryption key: $KEY_NAME"

if az keyvault key show --vault-name "$KEY_VAULT" --name "$KEY_NAME" >/dev/null 2>&1; then
  # Guarded so a re-run does not create a second key version. A new version would not break
  # decryption of existing state, but it is churn on a tier-0 asset for no reason.
  note_skipped "key $KEY_NAME"
else
  # --ops encrypt decrypt, NOT wrapKey/unwrapKey. Despite wrapping a data-encryption key, the
  # azure_vault provider calls the key's /encrypt and /decrypt endpoints (RSA-OAEP-256). A key
  # with only wrapKey/unwrapKey is rejected at `tofu init` with:
  #   403 Forbidden — "Operation encrypt is not permitted on this key."
  az keyvault key create \
    --vault-name "$KEY_VAULT" \
    --name "$KEY_NAME" \
    --kty RSA \
    --size 3072 \
    --ops encrypt decrypt \
    --output none
  note_created "key $KEY_NAME (RSA 3072, encrypt/decrypt)"
fi

# --------------------------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------------------------

step "Bootstrap complete"

echo "  created: ${#created[@]}   already existed: ${#skipped[@]}"
echo
echo "These values identify a real tenant — they are NOT committed. backend.hcl and"
echo "terraform.tfvars are git-ignored; the .example files in the repo are placeholders."
echo
echo "--- platform/backend.hcl ---------------------------------------------------------"
cat <<EOF
resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$STORAGE_ACCOUNT"
subscription_id      = "$SUBSCRIPTION_ID"
EOF
echo "# No tenant_id here on purpose — the backend rejects subscription and tenant together."
echo "--- platform/terraform.tfvars ----------------------------------------------------"
cat <<EOF
tenant_id                  = "$TENANT_ID"
platform_subscription_id   = "$SUBSCRIPTION_ID"
location                   = "$LOCATION"
state_storage_account_name = "$STORAGE_ACCOUNT"
state_key_vault_name       = "$KEY_VAULT"
state_key_vault_uri        = "$VAULT_URI"
EOF
echo "----------------------------------------------------------------------------------"
echo
echo "Next:"
echo "  1. Write those two files into platform/."
echo "  2. cd platform && tofu init -backend-config=backend.hcl"
echo "  3. tofu plan     # adopts these four resources, creates the rest"
echo "  4. tofu apply"
echo "  5. tofu plan     # must report zero changes"
echo
echo "No passphrase and no environment variable are needed for state encryption —"
echo "the azure_vault key provider authenticates as you."
