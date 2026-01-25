#!/bin/bash
# diagnose-unscheduled-pods.sh
#
# Diagnoses which pods could not be scheduled and why
#
# Usage:
#   ./diagnose-unscheduled-pods.sh <context>
#
# Examples:
#   ./diagnose-unscheduled-pods.sh kind-cluster-default
#   ./diagnose-unscheduled-pods.sh kind-cluster-bin-packing

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <context>"
    echo ""
    echo "Examples:"
    echo "  $0 kind-cluster-default"
    echo "  $0 kind-cluster-bin-packing"
    echo ""
    exit 1
fi

CONTEXT="$1"

echo "════════════════════════════════════════════════════════════════"
echo "  Pod Scheduling Diagnosis"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Context: $CONTEXT"
echo ""

# Verify context is accessible
if ! kubectl cluster-info --context "$CONTEXT" &>/dev/null; then
    echo "Error: Cannot access cluster with context '$CONTEXT'"
    exit 1
fi

echo "✓ Connected to cluster"
echo ""

# 1. Check Pending Pods
echo "════════════════════════════════════════════════════════════════"
echo "  1. Pending Pods (Not Yet Scheduled)"
echo "════════════════════════════════════════════════════════════════"
echo ""

PENDING_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
    --field-selector=status.phase=Pending -o json 2>/dev/null)

PENDING_COUNT=$(echo "$PENDING_PODS" | jq -r '.items | length' 2>/dev/null || echo "0")

if [ "$PENDING_COUNT" -eq 0 ]; then
    echo "✓ No pending pods - all existing pods are scheduled"
else
    echo "⚠️  Found $PENDING_COUNT pending pod(s):"
    echo ""
    
    echo "$PENDING_PODS" | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' | \
        while read pod; do
            NS=$(echo "$pod" | cut -d'/' -f1)
            NAME=$(echo "$pod" | cut -d'/' -f2)
            
            echo "  Pod: $pod"
            
            # Get scheduling reason
            REASON=$(kubectl get pod "$NAME" -n "$NS" --context "$CONTEXT" \
                -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}' 2>/dev/null || echo "Unknown")
            MESSAGE=$(kubectl get pod "$NAME" -n "$NS" --context "$CONTEXT" \
                -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].message}' 2>/dev/null || echo "No message")
            
            echo "    Reason: $REASON"
            echo "    Message: $MESSAGE"
            
            # Get resource requests
            REQUESTS=$(kubectl get pod "$NAME" -n "$NS" --context "$CONTEXT" \
                -o jsonpath='{.spec.containers[*].resources.requests}' 2>/dev/null || echo "No requests")
            echo "    Resource Requests: $REQUESTS"
            
            echo ""
        done
fi

echo ""

# 2. Check Deployment Replica Status
echo "════════════════════════════════════════════════════════════════"
echo "  2. Deployment Replica Status (Missing Pods)"
echo "════════════════════════════════════════════════════════════════"
echo ""

DEPLOYMENTS=$(kubectl get deployments --all-namespaces --context "$CONTEXT" \
    -o json 2>/dev/null)

echo "$DEPLOYMENTS" | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)|\(.spec.replicas // 0)|\(.status.replicas // 0)|\(.status.readyReplicas // 0)|\(.status.availableReplicas // 0)"' | \
    while IFS='|' read -r ns name desired current ready available; do
        if [ "$desired" != "$current" ] || [ "$desired" != "$ready" ]; then
            MISSING=$((desired - current))
            echo "  Deployment: $ns/$name"
            echo "    Desired:  $desired"
            echo "    Current:  $current"
            echo "    Ready:    $ready"
            echo "    Available: $available"
            if [ "$MISSING" -gt 0 ]; then
                echo "    ⚠️  Missing: $MISSING pod(s) not created"
            fi
            echo ""
        fi
    done

# Count deployments with missing replicas
MISSING_DEPLOYMENTS=$(echo "$DEPLOYMENTS" | jq -r '.items[] | select((.spec.replicas // 0) != (.status.replicas // 0) or (.spec.replicas // 0) != (.status.readyReplicas // 0)) | .metadata.name' | wc -l | tr -d ' ')

if [ "$MISSING_DEPLOYMENTS" -eq 0 ]; then
    echo "✓ All deployments have all replicas created and ready"
else
    echo "⚠️  Found $MISSING_DEPLOYMENTS deployment(s) with missing replicas"
fi

echo ""

# 3. Check ReplicaSet Status
echo "════════════════════════════════════════════════════════════════"
echo "  3. ReplicaSet Status (Detailed Pod Creation)"
echo "════════════════════════════════════════════════════════════════"
echo ""

REPLICASETS=$(kubectl get replicasets --all-namespaces --context "$CONTEXT" \
    -o json 2>/dev/null)

echo "$REPLICASETS" | jq -r '.items[] | select((.spec.replicas // 0) != (.status.readyReplicas // 0)) | "\(.metadata.namespace)|\(.metadata.name)|\(.spec.replicas // 0)|\(.status.replicas // 0)|\(.status.readyReplicas // 0)"' | \
    while IFS='|' read -r ns name desired current ready; do
        if [ "$desired" != "$ready" ]; then
            MISSING=$((desired - ready))
            echo "  ReplicaSet: $ns/$name"
            echo "    Desired:  $desired"
            echo "    Current:  $current"
            echo "    Ready:    $ready"
            echo "    ⚠️  Missing: $MISSING pod(s)"
            
            # Get pod status for this replicaset
            SELECTOR=$(kubectl get replicaset "$name" -n "$NS" --context "$CONTEXT" \
                -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null | \
                jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")' 2>/dev/null || echo "")
            
            if [ -n "$SELECTOR" ]; then
                echo "    Pods:"
                kubectl get pods -n "$ns" --context "$CONTEXT" -l "$SELECTOR" \
                    -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
NODE:.spec.nodeName,\
REASON:.status.reason 2>/dev/null | tail -n +2 | \
                    sed 's/^/      /' || echo "      (no pods found)"
            fi
            echo ""
        fi
    done

echo ""

# 4. Check Recent Events
echo "════════════════════════════════════════════════════════════════"
echo "  4. Recent Scheduling Events"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "Recent events related to pod scheduling:"
echo ""

kubectl get events --all-namespaces --context "$CONTEXT" \
    --sort-by='.lastTimestamp' 2>/dev/null | \
    grep -iE "(FailedCreate|FailedScheduling|Insufficient|Unschedulable)" | \
    tail -20 | \
    awk '{printf "  %s/%s: %s - %s\n", $1, $2, $4, $5}' || \
    echo "  (no recent scheduling events found)"

echo ""

# 5. Check Node Resource Availability
echo "════════════════════════════════════════════════════════════════"
echo "  5. Node Resource Availability"
echo "════════════════════════════════════════════════════════════════"
echo ""

kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
    jq -r '.items[] | "\(.metadata.name)|\(.status.allocatable.cpu)|\(.status.allocatable.memory)"' | \
    while IFS='|' read -r node cpu memory; do
        echo "  Node: $node"
        echo "    Allocatable CPU: $cpu"
        echo "    Allocatable Memory: $memory"
        
        # Get allocated resources
        kubectl describe node "$node" --context "$CONTEXT" 2>/dev/null | \
            grep -A 10 "Allocated resources" | \
            grep -E "(cpu|memory)" | \
            sed 's/^/      /' || echo "      (unable to get allocation)"
        echo ""
    done

echo ""

# 6. Summary
echo "════════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════════"
echo ""

TOTAL_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
    -o json 2>/dev/null | jq -r '.items | length' | tr -d ' ')

SCHEDULED_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
    -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .metadata.name' | wc -l | tr -d ' ')

PENDING_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
    --field-selector=status.phase=Pending -o json 2>/dev/null | \
    jq -r '.items | length' 2>/dev/null || echo "0")

TOTAL_DESIRED=$(echo "$DEPLOYMENTS" | jq -r '[.items[].spec.replicas // 0] | add' 2>/dev/null || echo "0")
TOTAL_CURRENT=$(echo "$DEPLOYMENTS" | jq -r '[.items[].status.replicas // 0] | add' 2>/dev/null || echo "0")
TOTAL_READY=$(echo "$DEPLOYMENTS" | jq -r '[.items[].status.readyReplicas // 0] | add' 2>/dev/null || echo "0")

MISSING_REPLICAS=$((TOTAL_DESIRED - TOTAL_CURRENT))

echo "Total Pods in Cluster:        $TOTAL_PODS"
echo "Scheduled Pods:              $SCHEDULED_PODS"
echo "Pending Pods:                $PENDING_COUNT"
echo ""
echo "Total Desired Replicas:      $TOTAL_DESIRED"
echo "Total Current Replicas:      $TOTAL_CURRENT"
echo "Total Ready Replicas:        $TOTAL_READY"
if [ "$MISSING_REPLICAS" -gt 0 ]; then
    echo "Missing Replicas:            $MISSING_REPLICAS ⚠️"
    echo ""
    echo "💡 $MISSING_REPLICAS pod(s) were not created by deployments"
    echo "   These are the pods that 'could not get scheduled'"
    echo "   Check deployment status above for details"
else
    echo "Missing Replicas:            0 ✓"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Diagnosis Complete"
echo "════════════════════════════════════════════════════════════════"
echo ""
