#!/bin/bash
# Script to find and delete KommanderCluster resources that reference a specific vcluster endpoint

WORKSPACE="${1:-my-workspace}"
VCLUSTER_NAME="${2:-vc-0001}"
VCLUSTER_NAMESPACE="${3:-vcluster-0001}"
TARGET_ENDPOINT="${VCLUSTER_NAME}.${VCLUSTER_NAMESPACE}"

echo "════════════════════════════════════════════════════════════════"
echo "Finding and deleting KommanderCluster resources"
echo "Workspace: $WORKSPACE"
echo "Looking for endpoint: $TARGET_ENDPOINT"
echo "════════════════════════════════════════════════════════════════"

# Get all KommanderCluster resources in the workspace
echo "Listing all KommanderCluster resources..."
kubectl get kommandercluster -n "$WORKSPACE" -o wide 2>/dev/null || {
    echo "No KommanderCluster resources found"
    exit 0
}

echo ""
echo "Checking each KommanderCluster for matching endpoint..."

# Get all KommanderCluster names
kubectl get kommandercluster -n "$WORKSPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | while read -r kc_name; do
    if [ -z "$kc_name" ]; then
        continue
    fi

    echo ""
    echo "Checking: $kc_name"

    # Get the kubeconfigRef secret name
    secret_name=$(kubectl get kommandercluster "$kc_name" -n "$WORKSPACE" -o jsonpath='{.spec.kubeconfigRef.name}' 2>/dev/null)

    if [ -z "$secret_name" ]; then
        echo "  ⚠ No kubeconfigRef found, skipping"
        continue
    fi

    echo "  Secret: $secret_name"

    # Get the secret and extract server endpoint
    TEMP_KUBECONFIG=$(mktemp)
    kubectl get secret "$secret_name" -n "$WORKSPACE" -o jsonpath='{.data.kubeconfig}' 2>/dev/null | base64 -d > "$TEMP_KUBECONFIG" 2>/dev/null

    if [ ! -s "$TEMP_KUBECONFIG" ]; then
        echo "  ⚠ Could not read secret"
        rm -f "$TEMP_KUBECONFIG"
        continue
    fi

    # Extract server endpoint (works on both macOS and Linux)
    SERVER_ENDPOINT=$(grep -E '^\s*server:\s*' "$TEMP_KUBECONFIG" | head -1 | sed -E 's/.*server:[[:space:]]*//' | tr -d '"')
    rm -f "$TEMP_KUBECONFIG"

    if [ -z "$SERVER_ENDPOINT" ]; then
        echo "  ⚠ Could not extract server endpoint"
        continue
    fi

    echo "  Server: $SERVER_ENDPOINT"

    # Check if this endpoint matches our vcluster (check for the shorter DNS name)
    if echo "$SERVER_ENDPOINT" | grep -q "$TARGET_ENDPOINT"; then
        echo "  ✓ MATCH! Deleting KommanderCluster: $kc_name"
        kubectl delete kommandercluster "$kc_name" -n "$WORKSPACE" --wait=false 2>/dev/null || true
        # Remove finalizers if stuck
        kubectl patch kommandercluster "$kc_name" -n "$WORKSPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    else
        echo "  - Different endpoint, keeping"
    fi
done

echo ""
echo "Waiting for deletions to complete..."
sleep 5

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Verifying cleanup"
echo "════════════════════════════════════════════════════════════════"
REMAINING=$(kubectl get kommandercluster -n "$WORKSPACE" 2>/dev/null | wc -l)
if [ "$REMAINING" -le 1 ]; then
    echo "✓ All matching KommanderCluster resources deleted"
else
    echo "⚠ Some KommanderCluster resources still exist:"
    kubectl get kommandercluster -n "$WORKSPACE"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Next step: Re-attach the vcluster"
echo "════════════════════════════════════════════════════════════════"
echo "  ./nutanix-nkp/nkp-attach attach-vcluster $VCLUSTER_NAME --workspace $WORKSPACE"
echo ""
