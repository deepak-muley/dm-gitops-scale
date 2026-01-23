#!/bin/bash
# Force cleanup script for KommanderCluster - finds and deletes ALL references

WORKSPACE="${1:-my-workspace}"
VCLUSTER_NAME="${2:-vc-0001}"
VCLUSTER_NAMESPACE="${3:-vcluster-0001}"
TARGET_ENDPOINT="${VCLUSTER_NAME}.${VCLUSTER_NAMESPACE}"

echo "════════════════════════════════════════════════════════════════"
echo "FORCE CLEANUP: KommanderCluster resources"
echo "Workspace: $WORKSPACE"
echo "Target endpoint: $TARGET_ENDPOINT"
echo "════════════════════════════════════════════════════════════════"

# Step 1: Delete ALL KommanderCluster resources in the workspace
echo ""
echo "Step 1: Deleting ALL KommanderCluster resources in $WORKSPACE..."
ALL_KC=$(kubectl get kommandercluster -n "$WORKSPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -n "$ALL_KC" ]; then
    for kc in $ALL_KC; do
        echo "  Deleting: $kc"
        kubectl delete kommandercluster "$kc" -n "$WORKSPACE" --wait=false --grace-period=0 2>/dev/null || true
        kubectl patch kommandercluster "$kc" -n "$WORKSPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
else
    echo "  No KommanderCluster resources found"
fi

# Step 2: Wait and verify
echo ""
echo "Step 2: Waiting for deletions..."
sleep 5

# Step 3: Check for any remaining (including terminating)
echo ""
echo "Step 3: Checking for remaining resources..."
REMAINING=$(kubectl get kommandercluster -n "$WORKSPACE" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
if [ "$REMAINING" -gt 0 ]; then
    echo "  ⚠ Found $REMAINING remaining KommanderCluster resources:"
    kubectl get kommandercluster -n "$WORKSPACE"
    echo ""
    echo "  Force deleting remaining resources..."
    kubectl get kommandercluster -n "$WORKSPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | while read -r kc; do
        if [ -n "$kc" ]; then
            echo "    Force deleting: $kc"
            kubectl delete kommandercluster "$kc" -n "$WORKSPACE" --force --grace-period=0 2>/dev/null || true
            kubectl patch kommandercluster "$kc" -n "$WORKSPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
    done
    sleep 3
fi

# Step 4: Delete all secrets that might be related
echo ""
echo "Step 4: Cleaning up related secrets..."
for secret in $(kubectl get secrets -n "$WORKSPACE" -o name 2>/dev/null | grep -E "attached|vc-0001"); do
    echo "  Deleting secret: $secret"
    kubectl delete "$secret" -n "$WORKSPACE" 2>/dev/null || true
done

# Step 5: Final verification
echo ""
echo "Step 5: Final verification..."
FINAL_CHECK=$(kubectl get kommandercluster -n "$WORKSPACE" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
if [ "$FINAL_CHECK" -eq 0 ]; then
    echo "  ✓ All KommanderCluster resources deleted"
else
    echo "  ⚠ Warning: $FINAL_CHECK KommanderCluster resources still exist:"
    kubectl get kommandercluster -n "$WORKSPACE"
    echo ""
    echo "  You may need to wait longer or check for finalizers"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "IMPORTANT: NKP may have internal state that needs time to clear"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "If re-attach still fails with 'already attached' error:"
echo "  1. Wait 30-60 seconds for NKP to clear internal state"
echo "  2. Try re-attaching again"
echo "  3. If still fails, you may need to use NKP CLI to detach, or"
echo "     contact NKP support to clear the internal state"
echo ""
echo "Re-attach command:"
echo "  ./nutanix-nkp/nkp-attach attach-vcluster $VCLUSTER_NAME --workspace $WORKSPACE"
echo ""
