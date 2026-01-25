#!/bin/bash
# cluster-metrics-analyzer.sh
#
# Analyzes any Kubernetes cluster to show:
# - Pod distribution across nodes
# - Node resource utilization (CPU/Memory)
# - Resource allocation details
# - Bin packing indicators
#
# Usage:
#   ./cluster-metrics-analyzer.sh [context]
#   context: Kubernetes context name (default: current context)
#
# Examples:
#   ./cluster-metrics-analyzer.sh
#   ./cluster-metrics-analyzer.sh kind-bin-packing-demo
#   ./cluster-metrics-analyzer.sh my-production-cluster
#
# Environment:
#   KUBECONFIG: Path to kubeconfig file (optional)
#   CONTEXT: Kubernetes context to use (optional)

set -e

CONTEXT="${1:-${CONTEXT:-$(kubectl config current-context 2>/dev/null || echo "")}}"

if [ -z "$CONTEXT" ]; then
    echo "Error: No Kubernetes context specified and no current context found."
    echo ""
    echo "Usage:"
    echo "  ./cluster-metrics-analyzer.sh [context]"
    echo ""
    echo "Examples:"
    echo "  ./cluster-metrics-analyzer.sh kind-bin-packing-demo"
    echo "  ./cluster-metrics-analyzer.sh my-cluster-context"
    echo ""
    echo "Or set KUBECONFIG environment variable:"
    echo "  export KUBECONFIG=/path/to/kubeconfig"
    echo "  ./cluster-metrics-analyzer.sh"
    echo ""
    exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "  Kubernetes Cluster Metrics Analyzer"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Context: $CONTEXT"
echo ""

# Verify context is accessible
if ! kubectl cluster-info --context "$CONTEXT" &>/dev/null; then
    echo "Error: Cannot access cluster with context '$CONTEXT'"
    echo ""
    echo "Available contexts:"
    kubectl config get-contexts -o name 2>/dev/null || echo "  (none found)"
    echo ""
    exit 1
fi

echo "✓ Connected to cluster"
echo ""

# Get cluster information
get_cluster_info() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Cluster Information"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Kubernetes version
    K8S_VERSION=$(kubectl version --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.serverVersion.gitVersion' 2>/dev/null || echo "unknown")
    echo "Kubernetes Version: $K8S_VERSION"
    
    # Node count
    NODE_COUNT=$(kubectl get nodes --context "$CONTEXT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "Node Count: $NODE_COUNT"
    
    # Total pod count
    POD_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "Total Pods: $POD_COUNT"
    
    # Cluster resource capacity
    TOTAL_CPU_CAP=$(kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '[.items[].status.capacity.cpu] | map(tonumber? // 0) | add' | \
        awk '{printf "%.2f", $1}' || echo "0")
    TOTAL_MEM_CAP=$(kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[].status.capacity.memory // "0"' 2>/dev/null | \
        awk '{
            if ($0 ~ /Gi/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024 * 1024 * 1024
            } else if ($0 ~ /Mi/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024 * 1024
            } else if ($0 ~ /Ki/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024
            } else if ($0 ~ /^[0-9]+$/) {
                sum += $0
            }
        } END {
            if (sum > 0) printf "%.0f", sum/1024/1024/1024
            else print "0"
        }' || echo "0")
    TOTAL_CPU_ALLOC=$(kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '[.items[].status.allocatable.cpu] | map(tonumber? // 0) | add' | \
        awk '{printf "%.2f", $1}' || echo "0")
    TOTAL_MEM_ALLOC=$(kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[].status.allocatable.memory // "0"' 2>/dev/null | \
        awk '{
            if ($0 ~ /Gi/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024 * 1024 * 1024
            } else if ($0 ~ /Mi/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024 * 1024
            } else if ($0 ~ /Ki/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024
            } else if ($0 ~ /^[0-9]+$/) {
                sum += $0
            }
        } END {
            if (sum > 0) printf "%.0f", sum/1024/1024/1024
            else print "0"
        }' || echo "0")
    
    echo ""
    echo "Cluster Resource Capacity:"
    echo "  Total CPU Capacity:     ${TOTAL_CPU_CAP} cores"
    echo "  Total Memory Capacity:  ${TOTAL_MEM_CAP} Gi"
    echo "  CPU Allocatable:       ${TOTAL_CPU_ALLOC} cores"
    echo "  Memory Allocatable:    ${TOTAL_MEM_ALLOC} Gi"
    echo "  (Allocatable = Capacity minus system reservations)"
    
    echo ""
}

# Show node resource utilization
show_node_utilization() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Node Resource Utilization"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    if kubectl top nodes --context "$CONTEXT" &>/dev/null; then
        kubectl top nodes --context "$CONTEXT"
        
        echo ""
        echo "Node Capacity:"
        kubectl get nodes --context "$CONTEXT" -o custom-columns=\
NAME:.metadata.name,\
CPU-Capacity:.status.capacity.cpu,\
MEMORY-Capacity:.status.capacity.memory,\
CPU-Allocatable:.status.allocatable.cpu,\
MEMORY-Allocatable:.status.allocatable.memory 2>/dev/null || echo "  (unable to get node details)"
    else
        echo "Metrics-server not available or still collecting data."
        echo ""
        echo "Node Capacity (without utilization metrics):"
        kubectl get nodes --context "$CONTEXT" -o custom-columns=\
NAME:.metadata.name,\
CPU:.status.capacity.cpu,\
MEMORY:.status.capacity.memory 2>/dev/null || echo "  (unable to get node details)"
    fi
    
    echo ""
}

# Show pod distribution
show_pod_distribution() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Pod Distribution Across Nodes"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    echo "All Pods (All Namespaces):"
    echo ""
    # Use JSON output to reliably get node name, even for Pending pods
    kubectl get pods --all-namespaces --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
        sort | uniq -c | sort -rn | \
        awk '{printf "  %-40s: %d pods\n", $2, $1}' || echo "  (no pods found)"
    
    # Show pod status breakdown
    echo ""
    echo "Pod Status Breakdown:"
    RUNNING_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l | tr -d ' ')
    PENDING_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ')
    FAILED_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.phase == "Failed") | .metadata.name' | wc -l | tr -d ' ')
    SUCCEEDED_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.phase == "Succeeded") | .metadata.name' | wc -l | tr -d ' ')
    UNKNOWN_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.phase == "Unknown" or .status.phase == null) | .metadata.name' | wc -l | tr -d ' ')
    
    echo "  Running:   $RUNNING_COUNT"
    echo "  Pending:   $PENDING_COUNT"
    if [ "$FAILED_COUNT" -gt 0 ]; then
        echo "  Failed:    $FAILED_COUNT"
    fi
    if [ "$SUCCEEDED_COUNT" -gt 0 ]; then
        echo "  Succeeded: $SUCCEEDED_COUNT"
    fi
    if [ "$UNKNOWN_COUNT" -gt 0 ]; then
        echo "  Unknown:   $UNKNOWN_COUNT"
    fi
    
    echo ""
    echo "By Namespace:"
    echo ""
    
    # Get all namespaces with pods
    NAMESPACES=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | \
        sort -u)
    
    for ns in $NAMESPACES; do
        POD_COUNT=$(kubectl get pods -n "$ns" --context "$CONTEXT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$POD_COUNT" -gt 0 ]; then
            echo "Namespace: $ns ($POD_COUNT pods)"
            # Use JSON output to reliably get node name
            kubectl get pods -n "$ns" --context "$CONTEXT" -o json 2>/dev/null | \
                jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
                sort | uniq -c | sort -rn | \
                awk '{printf "    %-38s: %d pods\n", $2, $1}' || echo "    (no pods)"
            
            # Count Pending pods in this namespace
            NS_PENDING=$(kubectl get pods -n "$ns" --context "$CONTEXT" -o json 2>/dev/null | \
                jq -r '.items[] | select(.spec.nodeName == null) | .metadata.name' | wc -l | tr -d ' ')
            if [ "$NS_PENDING" -gt 0 ]; then
                echo "    <pending> (not yet scheduled): $NS_PENDING pods"
            fi
            echo ""
        fi
    done
}

# Show resource allocation details
show_resource_allocation() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Detailed Node Resource Allocation"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    kubectl describe nodes --context "$CONTEXT" | grep -A 20 "Allocated resources" || {
        echo "Unable to get detailed allocation. Showing node summary:"
        kubectl get nodes --context "$CONTEXT" -o wide
    }
    
    echo ""
}

# Analyze bin packing indicators
analyze_bin_packing() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Bin Packing Analysis"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Get pod distribution using JSON for reliability
    DISTRIBUTION=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
        sort | uniq -c | sort -rn)
    
    if [ -z "$DISTRIBUTION" ]; then
        echo "No pods found to analyze."
        return
    fi
    
    # Calculate statistics
    NODE_COUNT=$(echo "$DISTRIBUTION" | wc -l | tr -d ' ')
    TOTAL_PODS=$(echo "$DISTRIBUTION" | awk '{sum+=$1} END {print sum}')
    AVG_PODS_PER_NODE=$((TOTAL_PODS / NODE_COUNT))
    
    # Get min and max pods per node
    MIN_PODS=$(echo "$DISTRIBUTION" | tail -1 | awk '{print $1}')
    MAX_PODS=$(echo "$DISTRIBUTION" | head -1 | awk '{print $1}')
    
    # Calculate variance (simple measure of distribution evenness)
    VARIANCE=$(echo "$DISTRIBUTION" | awk -v avg="$AVG_PODS_PER_NODE" \
        '{sum+=($1-avg)^2} END {print sum/NR}')
    
    # Count nodes with 0 pods
    ZERO_POD_NODES=$(kubectl get nodes --context "$CONTEXT" --no-headers 2>/dev/null | \
        awk '{print $1}' | while read node; do
            POD_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
                -o wide --no-headers 2>/dev/null | grep "$node" | wc -l | tr -d ' ')
            [ "$POD_COUNT" -eq 0 ] && echo "$node"
        done | wc -l | tr -d ' ')
    
    echo "Distribution Statistics:"
    echo "  Total Nodes: $NODE_COUNT"
    echo "  Total Pods: $TOTAL_PODS"
    echo "  Average Pods per Node: $AVG_PODS_PER_NODE"
    echo "  Min Pods per Node: $MIN_PODS"
    echo "  Max Pods per Node: $MAX_PODS"
    echo "  Nodes with 0 Pods: $ZERO_POD_NODES"
    echo ""
    
    # Calculate distribution ratio (max/min)
    if [ "$MIN_PODS" -gt 0 ]; then
        RATIO=$(echo "scale=2; $MAX_PODS / $MIN_PODS" | bc 2>/dev/null || echo "N/A")
        echo "  Distribution Ratio (Max/Min): $RATIO"
    fi
    
    echo ""
    echo "Bin Packing Indicators:"
    echo ""
    
    # Analyze pattern
    if [ "$ZERO_POD_NODES" -gt 0 ]; then
        echo "  ✅ Some nodes have 0 pods (bin packing likely enabled)"
        echo "     → $ZERO_POD_NODES node(s) available for workloads"
    else
        echo "  ⚠️  All nodes have pods (may indicate default scheduler)"
    fi
    
    if [ -n "$RATIO" ] && [ "$RATIO" != "N/A" ]; then
        RATIO_INT=$(echo "$RATIO" | cut -d. -f1)
        if [ "$RATIO_INT" -gt 2 ]; then
            echo "  ✅ High distribution variance (bin packing likely enabled)"
            echo "     → Pods concentrated on fewer nodes"
        elif [ "$RATIO_INT" -gt 1 ]; then
            echo "  ⚠️  Moderate distribution variance"
            echo "     → Some concentration, but not extreme"
        else
            echo "  ⚠️  Low distribution variance (default scheduler likely)"
            echo "     → Pods spread relatively evenly"
        fi
    fi
    
    # Check scheduler configuration
    echo ""
    echo "Scheduler Configuration Check:"
    SCHEDULER_LOGS=$(kubectl logs -n kube-system --context "$CONTEXT" \
        -l component=kube-scheduler --tail=50 2>/dev/null | \
        grep -i "mostallocated\|requestedtocapacityratio\|bin\|pack" || echo "")
    
    if [ -n "$SCHEDULER_LOGS" ]; then
        echo "  ✅ Bin packing scheduler detected in logs"
        echo "     Scheduler appears to be using bin packing strategy"
    else
        echo "  ⚠️  No bin packing indicators in scheduler logs"
        echo "     (May be using default LeastAllocated strategy)"
    fi
    
    echo ""
}

# Show top resource consumers
show_top_consumers() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Top Resource Consumers"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    if kubectl top pods --all-namespaces --context "$CONTEXT" &>/dev/null; then
        echo "Top CPU Consumers:"
        kubectl top pods --all-namespaces --context "$CONTEXT" --sort-by=cpu | head -10
        echo ""
        echo "Top Memory Consumers:"
        kubectl top pods --all-namespaces --context "$CONTEXT" --sort-by=memory | head -10
    else
        echo "Metrics-server not available for pod-level metrics."
        echo "Showing resource requests instead:"
        echo ""
        kubectl get pods --all-namespaces --context "$CONTEXT" -o json 2>/dev/null | \
            jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)\t\(.spec.containers[0].resources.requests.cpu // "N/A")\t\(.spec.containers[0].resources.requests.memory // "N/A")"' | \
            head -20 | column -t || echo "  (unable to get resource requests)"
    fi
    
    echo ""
}

# Generate summary report
generate_summary() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Summary Report"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Get key metrics
    NODE_COUNT=$(kubectl get nodes --context "$CONTEXT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    POD_COUNT=$(kubectl get pods --all-namespaces --context "$CONTEXT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    # Get nodes with pods using JSON for reliability
    NODES_WITH_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
        sort -u | wc -l | tr -d ' ')
    
    NODES_AVAILABLE=$((NODE_COUNT - NODES_WITH_PODS))
    
    echo "Cluster Summary:"
    echo "  Total Nodes: $NODE_COUNT"
    echo "  Nodes with Pods: $NODES_WITH_PODS"
    echo "  Nodes Available: $NODES_AVAILABLE"
    echo "  Total Pods: $POD_COUNT"
    
    if [ "$NODE_COUNT" -gt 0 ]; then
        AVG_PODS=$((POD_COUNT / NODE_COUNT))
        echo "  Average Pods per Node: $AVG_PODS"
    fi
    
    echo ""
    
    # Utilization summary
    if kubectl top nodes --context "$CONTEXT" &>/dev/null; then
        echo "Average Node Utilization:"
        kubectl top nodes --context "$CONTEXT" 2>/dev/null | \
            awk 'NR>1 {cpu+=$3; mem+=$5; count++} END {
                if (count > 0) {
                    printf "  Average CPU: %.1f%%\n", cpu/count
                    printf "  Average Memory: %.1f%%\n", mem/count
                }
            }'
    fi
    
    echo ""
}

# Generate comparison highlights for easy side-by-side comparison
generate_comparison_highlights() {
    echo "════════════════════════════════════════════════════════════════"
    echo "  Comparison Highlights"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Key metrics to compare across cluster runs:"
    echo ""
    
    # Get key metrics
    NODE_COUNT=$(kubectl get nodes --context "$CONTEXT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    # Get cluster capacity
    TOTAL_CPU_CAP=$(kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '[.items[].status.capacity.cpu] | map(tonumber? // 0) | add' | \
        awk '{printf "%.2f", $1}' || echo "0")
    TOTAL_MEM_CAP=$(kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[].status.capacity.memory // "0"' 2>/dev/null | \
        awk '{
            if ($0 ~ /Gi/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024 * 1024 * 1024
            } else if ($0 ~ /Mi/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024 * 1024
            } else if ($0 ~ /Ki/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024
            } else if ($0 ~ /^[0-9]+$/) {
                sum += $0
            }
        } END {
            if (sum > 0) printf "%.0f", sum/1024/1024/1024
            else print "0"
        }' || echo "0")
    TOTAL_CPU_ALLOC=$(kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '[.items[].status.allocatable.cpu] | map(tonumber? // 0) | add' | \
        awk '{printf "%.2f", $1}' || echo "0")
    TOTAL_MEM_ALLOC=$(kubectl get nodes --context "$CONTEXT" -o json 2>/dev/null | \
        jq -r '.items[].status.allocatable.memory // "0"' 2>/dev/null | \
        awk '{
            if ($0 ~ /Gi/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024 * 1024 * 1024
            } else if ($0 ~ /Mi/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024 * 1024
            } else if ($0 ~ /Ki/i) {
                gsub(/[^0-9.]/, "", $0)
                sum += $0 * 1024
            } else if ($0 ~ /^[0-9]+$/) {
                sum += $0
            }
        } END {
            if (sum > 0) printf "%.0f", sum/1024/1024/1024
            else print "0"
        }' || echo "0")
    
    # Get scheduled pods (with nodes)
    SCHEDULED_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | wc -l | tr -d ' ')
    
    # Get pods by status
    RUNNING_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l | tr -d ' ')
    PENDING_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ')
    FAILED_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Failed") | .metadata.name' | wc -l | tr -d ' ')
    SUCCEEDED_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Succeeded") | .metadata.name' | wc -l | tr -d ' ')
    UNKNOWN_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Unknown" or .status.phase == null) | .metadata.name' | wc -l | tr -d ' ')
    
    TOTAL_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items | length' | tr -d ' ')
    
    # Get nodes with pods
    NODES_WITH_PODS=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
        sort -u | wc -l | tr -d ' ')
    
    NODES_AVAILABLE=$((NODE_COUNT - NODES_WITH_PODS))
    
    # Get pod distribution stats
    DISTRIBUTION=$(kubectl get pods --all-namespaces --context "$CONTEXT" \
        -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
        sort | uniq -c | sort -rn)
    
    if [ -n "$DISTRIBUTION" ]; then
        MIN_PODS=$(echo "$DISTRIBUTION" | tail -1 | awk '{print $1}')
        MAX_PODS=$(echo "$DISTRIBUTION" | head -1 | awk '{print $1}')
        AVG_PODS=$((SCHEDULED_PODS / NODES_WITH_PODS))
        
        if [ "$MIN_PODS" -gt 0 ]; then
            RATIO=$(echo "scale=2; $MAX_PODS / $MIN_PODS" | bc 2>/dev/null || echo "N/A")
        else
            RATIO="N/A"
        fi
    else
        MIN_PODS=0
        MAX_PODS=0
        AVG_PODS=0
        RATIO="N/A"
    fi
    
    # Get average utilization if available
    AVG_CPU="N/A"
    AVG_MEM="N/A"
    if kubectl top nodes --context "$CONTEXT" &>/dev/null; then
        AVG_CPU=$(kubectl top nodes --context "$CONTEXT" 2>/dev/null | \
            awk 'NR>1 {cpu+=$3; count++} END {if (count > 0) printf "%.1f%%", cpu/count; else print "N/A"}')
        AVG_MEM=$(kubectl top nodes --context "$CONTEXT" 2>/dev/null | \
            awk 'NR>1 {mem+=$5; count++} END {if (count > 0) printf "%.1f%%", mem/count; else print "N/A"}')
    fi
    
    # Print highlights in simple format
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ CLUSTER: $CONTEXT"
    printf "│ %-59s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ %-30s: %-26s │\n" "Total Nodes" "$NODE_COUNT"
    printf "│ %-30s: %-26s │\n" "CPU Capacity" "${TOTAL_CPU_CAP} cores"
    printf "│ %-30s: %-26s │\n" "Memory Capacity" "${TOTAL_MEM_CAP} Gi"
    printf "│ %-30s: %-26s │\n" "CPU Allocatable" "${TOTAL_CPU_ALLOC} cores"
    printf "│ %-30s: %-26s │\n" "Memory Allocatable" "${TOTAL_MEM_ALLOC} Gi"
    printf "│ %-30s: %-26s │\n" "Nodes with Pods" "$NODES_WITH_PODS"
    printf "│ %-30s: %-26s │\n" "Nodes Available" "$NODES_AVAILABLE"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ %-30s: %-26s │\n" "Total Pods (All Namespaces)" "$TOTAL_PODS"
    printf "│ %-30s: %-26s │\n" "Scheduled Pods" "$SCHEDULED_PODS"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ %-30s: %-26s │\n" "Pod Status Breakdown:" ""
    printf "│ %-30s: %-26s │\n" "  Running Pods" "$RUNNING_PODS"
    printf "│ %-30s: %-26s │\n" "  Pending Pods" "$PENDING_PODS"
    if [ "$FAILED_PODS" -gt 0 ]; then
        printf "│ %-30s: %-26s │\n" "  Failed Pods" "$FAILED_PODS"
    fi
    if [ "$SUCCEEDED_PODS" -gt 0 ]; then
        printf "│ %-30s: %-26s │\n" "  Succeeded Pods" "$SUCCEEDED_PODS"
    fi
    if [ "$UNKNOWN_PODS" -gt 0 ]; then
        printf "│ %-30s: %-26s │\n" "  Unknown Pods" "$UNKNOWN_PODS"
    fi
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ %-30s: %-26s │\n" "Avg Pods per Node" "$AVG_PODS"
    printf "│ %-30s: %-26s │\n" "Min Pods per Node" "$MIN_PODS"
    printf "│ %-30s: %-26s │\n" "Max Pods per Node" "$MAX_PODS"
    if [ "$RATIO" != "N/A" ]; then
        printf "│ %-30s: %-26s │\n" "Distribution Ratio (Max/Min)" "$RATIO"
    fi
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ %-30s: %-26s │\n" "Avg CPU Utilization" "$AVG_CPU"
    printf "│ %-30s: %-26s │\n" "Avg Memory Utilization" "$AVG_MEM"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "💡 What to Compare:"
    echo ""
    echo "  ✅ Nodes Available:"
    echo "     → Higher = Better (more capacity for scaling)"
    echo ""
    echo "  ✅ Scheduled Pods:"
    echo "     → Higher = Better (more workloads running)"
    echo ""
    echo "  ✅ Distribution Ratio (Max/Min):"
    echo "     → Higher = Bin packing working (pods concentrated)"
    echo "     → Lower = Even distribution (default scheduler)"
    echo ""
    echo "  ✅ Avg Pods per Node:"
    echo "     → Higher = Better utilization (more density)"
    echo ""
    echo "  ✅ Avg CPU/Memory Utilization:"
    echo "     → Higher = Better (more efficient resource usage)"
    echo ""
    echo "  ⚠️  Pending Pods:"
    echo "     → Lower = Better (fewer pods waiting)"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

# Main execution
main() {
    get_cluster_info
    show_node_utilization
    show_pod_distribution
    show_resource_allocation
    analyze_bin_packing
    show_top_consumers
    generate_summary
    generate_comparison_highlights
    
    echo "════════════════════════════════════════════════════════════════"
    echo "  Analysis Complete"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "To explore further:"
    echo "  kubectl get pods -A --context $CONTEXT -o wide"
    echo "  kubectl top nodes --context $CONTEXT"
    echo "  kubectl describe nodes --context $CONTEXT"
    echo ""
    echo "To compare two clusters, run this script twice:"
    echo "  ./cluster-metrics-analyzer.sh cluster-default > cluster-a.txt"
    echo "  ./cluster-metrics-analyzer.sh cluster-bin-packing > cluster-b.txt"
    echo "  diff cluster-a.txt cluster-b.txt"
    echo ""
}

# Run main
main
