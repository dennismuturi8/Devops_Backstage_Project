#!/bin/bash
# seal-secret.sh
# ─────────────────────────────────────────────────────────────────
# Generates sealed-db-credentials.yaml from secret.yaml using kubeseal.
# Run this ONCE locally after:
#   1. manage.sh up has completed (cluster is running + Sealed Secrets installed)
#   2. You have copied the public cert from the control plane
#
# Usage:
#   bash seal-secret.sh
#
# Output:
#   manifest/backstage/sealed-db-credentials.yaml  ← safe to commit to Git
# ─────────────────────────────────────────────────────────────────
set -e

SECRET_FILE="./secret.yaml"
OUTPUT_FILE="./manifest/backstage/sealed-db-credentials.yaml"
CERT_FILE="./sealed-secrets-pub.pem"
CONTROLLER_NAME="sealed-secrets-controller"
CONTROLLER_NS="kube-system"

# ── Preflight checks ──────────────────────────────────────────────
if ! command -v kubeseal &>/dev/null; then
  echo "❌ kubeseal not found. Install it first:"
  echo "   Linux:  wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz"
  echo "   Mac:    brew install kubeseal"
  exit 1
fi

if [[ ! -f "$SECRET_FILE" ]]; then
  echo "❌ $SECRET_FILE not found. Create it from the secret.yaml template first."
  exit 1
fi

# ── Seal using the public cert (offline — no cluster connection needed) ──
if [[ -f "$CERT_FILE" ]]; then
  echo "🔐 Sealing secret using local public cert..."
  kubeseal \
    --format yaml \
    --cert "$CERT_FILE" \
    < "$SECRET_FILE" \
    > "$OUTPUT_FILE"

# ── Or seal directly against the live cluster ──────────────────────
else
  echo "🔐 No local cert found — sealing directly against the cluster..."
  kubeseal \
    --format yaml \
    --controller-name "$CONTROLLER_NAME" \
    --controller-namespace "$CONTROLLER_NS" \
    < "$SECRET_FILE" \
    > "$OUTPUT_FILE"
fi

echo ""
echo "✅ Sealed secret written to: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the output file (it should contain encryptedData, not your password)"
echo "  2. git add $OUTPUT_FILE"
echo "  3. git commit -m 'chore: add sealed db credentials'"
echo "  4. git push origin main"
echo ""
echo "⚠️  Do NOT commit secret.yaml — it is in .gitignore but double-check."
