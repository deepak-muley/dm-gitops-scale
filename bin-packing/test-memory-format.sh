#!/bin/bash
# Quick test script to see actual memory format from nodes

CONTEXT="${1:-kind-cluster-default}"

echo "Testing memory format from nodes in context: $CONTEXT"
echo ""

echo "Raw memory values from nodes:"
kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
    jq -r '.items[] | "\(.metadata.name): \(.status.capacity.memory)"'

echo ""
echo "Allocatable memory values:"
kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
    jq -r '.items[] | "\(.metadata.name): \(.status.allocatable.memory)"'
