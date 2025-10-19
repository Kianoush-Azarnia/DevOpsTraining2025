#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Script Name: check-pod-secrets.sh
# Purpose: List all secrets referenced by pods in a namespace and export results to CSV
# Author: Kianoush (DevOps Audit)
# ---------------------------------------------------------------------------

# Prompt user for inputs
read -p "Enter the namespace: " NAMESPACE
read -p "Enter the kubeconfig path: " KUBECONFIG

# Trim whitespace (in case of copy/paste)
NAMESPACE=$(echo "$NAMESPACE" | xargs)
KUBECONFIG=$(echo "$KUBECONFIG" | xargs)

# Define report filename with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="pod-secrets-report_${NAMESPACE}_${TIMESTAMP}.csv"

echo ""
echo "🔍 Checking secrets usage in namespace: $NAMESPACE"
echo "Using kubeconfig: $KUBECONFIG"
echo "Results will be saved to: $REPORT_FILE"
echo "---------------------------------------------------"

# Validate namespace and kubeconfig
if ! kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" get pods &>/dev/null; then
  echo "❌ Namespace '$NAMESPACE' not accessible or contains no pods."
  exit 1
fi

# Write CSV header
echo "Namespace,Pod Name,Secret Name,Exists" > "$REPORT_FILE"

# Get all pods in namespace
PODS=$(kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" get pods -o name)

if [[ -z "$PODS" ]]; then
  echo "❌ No pods found in namespace: $NAMESPACE"
  exit 1
fi

# Loop through pods
for POD in $PODS; do
  POD_NAME=${POD#pod/}
  echo ""
  echo "🧩 Pod: $POD_NAME"
  echo "--------------------------------"

  # Extract referenced secrets
  SECRETS=$(kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" get pod "$POD_NAME" \
    -o jsonpath='{.spec.volumes[*].secret.secretName} {.spec.containers[*].env[*].valueFrom.secretKeyRef.name}' \
    | tr ' ' '\n' | sort -u | grep -v '^$')

  if [[ -z "$SECRETS" ]]; then
    echo "⚠️  No secrets referenced in this pod."
    echo "$NAMESPACE,$POD_NAME,None,No Secrets Referenced" >> "$REPORT_FILE"
  else
    echo "🔐 Secrets referenced:"
    for SECRET in $SECRETS; do
      echo "   - $SECRET"
      # Check if secret actually exists
      if kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" get secret "$SECRET" &>/dev/null; then
        echo "     ✅ Secret exists."
        echo "$NAMESPACE,$POD_NAME,$SECRET,Yes" >> "$REPORT_FILE"
      else
        echo "     ❌ Secret not found in cluster!"
        echo "$NAMESPACE,$POD_NAME,$SECRET,No" >> "$REPORT_FILE"
      fi
    done
  fi
done

echo ""
echo "✅ Secret audit complete for namespace: $NAMESPACE"
echo "📄 Report saved as: $REPORT_FILE"
echo "---------------------------------------------------"
