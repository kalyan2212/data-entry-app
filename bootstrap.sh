#!/bin/bash
# bootstrap.sh
# ─────────────────────────────────────────────────────────────────────────────
# Run this ONCE from your local machine (with Azure CLI installed and logged in)
# BEFORE running any Terraform commands.
#
# What it does:
#   1. Creates a Resource Group for Terraform remote state
#   2. Creates an Azure Storage Account + Blob Container for tfstate
#   3. Creates a Service Principal (app registration) for GitHub Actions
#   4. Prints every GitHub Secret you need to create
#
# Usage:
#   1. Install Azure CLI:  https://aka.ms/azurecli
#   2. Login:              az login
#   3. Edit SUBSCRIPTION_ID below with your real Azure Subscription GUID
#   4. Run:                bash bootstrap.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── EDIT THIS ─────────────────────────────────────────────────────────────────
SUBSCRIPTION_ID="YOUR-AZURE-SUBSCRIPTION-GUID-HERE"   # e.g. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ─────────────────────────────────────────────────────────────────────────────

LOCATION="eastus"
STATE_RG="data-entry-tf-state"
STORAGE_ACCOUNT="dataentrytfstate$RANDOM"   # globally unique; note the printed name
CONTAINER_NAME="tfstate"
APP_RG="data-entry"
SP_NAME="data-entry-github-deploy"

echo ""
echo "==========================================="
echo " Data Entry App – Bootstrap"
echo "==========================================="
echo " Subscription : $SUBSCRIPTION_ID"
echo " Location     : $LOCATION"
echo "==========================================="
echo ""

# ── Step 1: Set the active subscription ──────────────────────────────────────
echo "[1/5] Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

# ── Step 2: Resource group for Terraform state ───────────────────────────────
echo "[2/5] Creating resource group for Terraform state: $STATE_RG"
az group create --name "$STATE_RG" --location "$LOCATION" --output none

# ── Step 3: Storage account + container for tfstate ──────────────────────────
echo "[3/5] Creating storage account: $STORAGE_ACCOUNT"
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$STATE_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --encryption-services blob \
  --output none

az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --output none

# ── Step 4: Create application resource group (so SP has scope) ──────────────
echo "[4/5] Creating application resource group: $APP_RG"
az group create --name "$APP_RG" --location "$LOCATION" --output none

# ── Step 5: Service Principal for GitHub Actions ─────────────────────────────
echo "[5/5] Creating Service Principal: $SP_NAME"
SP_JSON=$(az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role Contributor \
  --scopes "/subscriptions/$SUBSCRIPTION_ID" \
  --sdk-auth \
  --output json)

CLIENT_ID=$(echo "$SP_JSON"     | python3 -c "import sys,json; print(json.load(sys.stdin)['clientId'])")
CLIENT_SECRET=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['clientSecret'])")
TENANT_ID=$(echo "$SP_JSON"     | python3 -c "import sys,json; print(json.load(sys.stdin)['tenantId'])")

# ── Print results ─────────────────────────────────────────────────────────────
echo ""
echo "==========================================================="
echo " BOOTSTRAP COMPLETE"
echo "==========================================================="
echo ""
echo " STEP A: Update terraform/main.tf backend block"
echo "   Change: storage_account_name = \"dataentrytfstateXXXX\""
echo "       To: storage_account_name = \"$STORAGE_ACCOUNT\""
echo ""
echo " STEP B: Push this repo to GitHub as kalyan2212/data-entry-app"
echo "   git init"
echo "   git remote add origin https://github.com/kalyan2212/data-entry-app.git"
echo "   git add ."
echo "   git commit -m 'initial commit'"
echo "   git push -u origin main"
echo ""
echo " STEP C: Add these GitHub Secrets"
echo "   Repository → Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "   Secret Name            │ Value"
echo "   ──────────────────────────────────────────────────────────"
echo "   AZURE_CLIENT_ID        │ $CLIENT_ID"
echo "   AZURE_CLIENT_SECRET    │ $CLIENT_SECRET"
echo "   AZURE_SUBSCRIPTION_ID  │ $SUBSCRIPTION_ID"
echo "   AZURE_TENANT_ID        │ $TENANT_ID"
echo "   VM_ADMIN_PASSWORD      │ <choose a strong password for VM OS login>"
echo "   DB_ADMIN_PASSWORD      │ <choose a strong password for PostgreSQL>"
echo "   APP_SECRET_KEY         │ <random 32+ char string for Flask sessions>"
echo "   UPSTREAM_API_KEY       │ <key you share with your upstream app>"
echo "   DOWNSTREAM_API_KEY     │ <key you share with your downstream app>"
echo ""
echo " STEP D: Push to main – GitHub Actions will:"
echo "   1. infra.yml  → terraform plan + apply  (provisions all Azure resources)"
echo "   2. deploy.yml → deploy app code to VMs  (runs after infra is up)"
echo ""
echo " STEP E: Access the app"
echo "   After deploy: terraform -chdir=terraform output load_balancer_public_ip"
echo "   Open: http://<that IP>/"
echo "==========================================================="
