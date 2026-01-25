#!/bin/bash
# compare-clusters.sh
#
# Compares two Kubernetes clusters side-by-side
#
# Usage:
#   ./compare-clusters.sh <context1> <context2>
#
# Examples:
#   ./compare-clusters.sh kind-cluster-default kind-cluster-bin-packing
#   ./compare-clusters.sh production-cluster staging-cluster

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <context1> <context2>"
    echo ""
    echo "Examples:"
    echo "  $0 kind-cluster-default kind-cluster-bin-packing"
    echo "  $0 production-cluster staging-cluster"
    echo ""
    exit 1
fi

CONTEXT1="$1"
CONTEXT2="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZER_SCRIPT="$SCRIPT_DIR/cluster-metrics-analyzer.sh"

if [ ! -f "$ANALYZER_SCRIPT" ]; then
    echo "Error: cluster-metrics-analyzer.sh not found at $ANALYZER_SCRIPT"
    exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "  Cluster Comparison Tool"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Comparing:"
echo "  Cluster A: $CONTEXT1"
echo "  Cluster B: $CONTEXT2"
echo ""

# Verify clusters are accessible
echo "Verifying cluster access..."
if ! kubectl cluster-info --context "$CONTEXT1" &>/dev/null; then
    echo "Error: Cannot access cluster '$CONTEXT1'"
    exit 1
fi

if ! kubectl cluster-info --context "$CONTEXT2" &>/dev/null; then
    echo "Error: Cannot access cluster '$CONTEXT2'"
    exit 1
fi

echo "✓ Both clusters accessible"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Side-by-Side Comparison"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Function to get a specific metric
get_metric() {
    local context="$1"
    local metric="$2"
    
    case "$metric" in
        "nodes")
            kubectl get nodes --context "$context" --no-headers 2>/dev/null | wc -l | tr -d ' '
            ;;
        "nodes_with_pods")
            kubectl get pods --all-namespaces --context "$context" \
                -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
                sort -u | wc -l | tr -d ' '
            ;;
        "nodes_available")
            local total=$(kubectl get nodes --context "$context" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            local with_pods=$(kubectl get pods --all-namespaces --context "$context" \
                -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
                sort -u | wc -l | tr -d ' ')
            echo $((total - with_pods))
            ;;
        "scheduled_pods")
            kubectl get pods --all-namespaces --context "$context" \
                -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | wc -l | tr -d ' '
            ;;
        "pending_pods")
            COUNT=$(kubectl get pods --all-namespaces --context "$context" \
                -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ')
            echo "${COUNT:-0}"
            ;;
        "failed_pods")
            COUNT=$(kubectl get pods --all-namespaces --context "$context" \
                -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Failed") | .metadata.name' | wc -l | tr -d ' ')
            echo "${COUNT:-0}"
            ;;
        "total_pods")
            COUNT=$(kubectl get pods --all-namespaces --context "$context" \
                -o json 2>/dev/null | jq -r '.items | length' | tr -d ' ')
            echo "${COUNT:-0}"
            ;;
        "max_pods_per_node")
            kubectl get pods --all-namespaces --context "$context" \
                -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
                sort | uniq -c | sort -rn | head -1 | awk '{print $1}'
            ;;
        "min_pods_per_node")
            kubectl get pods --all-namespaces --context "$context" \
                -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
                sort | uniq -c | sort -rn | tail -1 | awk '{print $1}'
            ;;
        "avg_cpu")
            kubectl top nodes --context "$context" 2>/dev/null | \
                awk 'NR>1 {cpu+=$3; count++} END {if (count > 0) printf "%.1f%%", cpu/count; else print "N/A"}'
            ;;
        "avg_mem")
            kubectl top nodes --context "$context" 2>/dev/null | \
                awk 'NR>1 {mem+=$5; count++} END {if (count > 0) printf "%.1f%%", mem/count; else print "N/A"}'
            ;;
        "total_cpu_capacity")
            RESULT=$(kubectl get nodes --context "$context" -o json 2>/dev/null | \
                jq -r '[.items[].status.capacity.cpu] | map(if type == "string" then (gsub("[^0-9.]"; "") | if . == "" then 0 else tonumber end) else . end) | add' 2>/dev/null)
            if [ -n "$RESULT" ] && [ "$RESULT" != "null" ] && [ "$RESULT" != "" ]; then
                echo "$RESULT" | awk '{printf "%.2f", $1}'
            else
                echo "0"
            fi
            ;;
        "total_memory_capacity")
            # Get memory values, parse units correctly, convert to GiB
            # Use simpler regex matching - check for unit suffix explicitly
            RESULT=$(kubectl get nodes --context "$context" -o json 2>/dev/null | \
                jq -r '.items[].status.capacity.memory // empty' 2>/dev/null | \
                awk 'BEGIN {sum=0} {
                    val = $0
                    if (val == "" || val == "null") next
                    # Check for unit suffix (must be at end, no optional groups)
                    if (val ~ /Ki$/) {
                        gsub(/Ki$/, "", val)
                        sum += val * 1024
                    } else if (val ~ /Mi$/) {
                        gsub(/Mi$/, "", val)
                        sum += val * 1024 * 1024
                    } else if (val ~ /Gi$/) {
                        gsub(/Gi$/, "", val)
                        sum += val * 1024 * 1024 * 1024
                    } else if (val ~ /Ti$/) {
                        gsub(/Ti$/, "", val)
                        sum += val * 1024 * 1024 * 1024 * 1024
                    } else if (val ~ /^[0-9]+$/) {
                        # Pure number - assume bytes
                        sum += val
                    }
                } END {
                    if (sum > 0) printf "%.0f", sum
                    else print "0"
                }')
            if [ -n "$RESULT" ] && [ "$RESULT" != "null" ] && [ "$RESULT" != "" ] && [ "$RESULT" != "0" ]; then
                # Convert bytes to GiB
                echo "$RESULT" | awk '{printf "%.0f", $1/1024/1024/1024}'
            else
                echo "0"
            fi
            ;;
        "total_cpu_allocatable")
            RESULT=$(kubectl get nodes --context "$context" -o json 2>/dev/null | \
                jq -r '[.items[].status.allocatable.cpu] | map(if type == "string" then (gsub("[^0-9.]"; "") | if . == "" then 0 else tonumber end) else . end) | add' 2>/dev/null)
            if [ -n "$RESULT" ] && [ "$RESULT" != "null" ] && [ "$RESULT" != "" ]; then
                echo "$RESULT" | awk '{printf "%.2f", $1}'
            else
                echo "0"
            fi
            ;;
        "total_memory_allocatable")
            # Get memory values, parse units correctly, convert to GiB
            # Use a simpler approach: check for unit suffix explicitly
            RESULT=$(kubectl get nodes --context "$context" -o json 2>/dev/null | \
                jq -r '.items[].status.allocatable.memory // empty' 2>/dev/null | \
                awk 'BEGIN {sum=0} {
                    val = $0
                    if (val == "" || val == "null") next
                    # Check for unit suffix (must be at end)
                    if (val ~ /Ki$/) {
                        gsub(/Ki$/, "", val)
                        sum += val * 1024
                    } else if (val ~ /Mi$/) {
                        gsub(/Mi$/, "", val)
                        sum += val * 1024 * 1024
                    } else if (val ~ /Gi$/) {
                        gsub(/Gi$/, "", val)
                        sum += val * 1024 * 1024 * 1024
                    } else if (val ~ /Ti$/) {
                        gsub(/Ti$/, "", val)
                        sum += val * 1024 * 1024 * 1024 * 1024
                    } else if (val ~ /^[0-9]+$/) {
                        # Pure number - assume bytes
                        sum += val
                    }
                } END {
                    if (sum > 0) printf "%.0f", sum
                    else print "0"
                }')
            if [ -n "$RESULT" ] && [ "$RESULT" != "null" ] && [ "$RESULT" != "" ] && [ "$RESULT" != "0" ]; then
                # Convert bytes to GiB
                echo "$RESULT" | awk '{printf "%.0f", $1/1024/1024/1024}'
            else
                echo "0"
            fi
            ;;
    esac
}

# Get metrics for both clusters
NODES1=$(get_metric "$CONTEXT1" "nodes")
NODES2=$(get_metric "$CONTEXT2" "nodes")

NODES_WITH_PODS1=$(get_metric "$CONTEXT1" "nodes_with_pods")
NODES_WITH_PODS2=$(get_metric "$CONTEXT2" "nodes_with_pods")

NODES_AVAILABLE1=$(get_metric "$CONTEXT1" "nodes_available")
NODES_AVAILABLE2=$(get_metric "$CONTEXT2" "nodes_available")

SCHEDULED1=$(get_metric "$CONTEXT1" "scheduled_pods")
SCHEDULED2=$(get_metric "$CONTEXT2" "scheduled_pods")

PENDING1=$(get_metric "$CONTEXT1" "pending_pods" || echo "0")
PENDING2=$(get_metric "$CONTEXT2" "pending_pods" || echo "0")

RUNNING1=$(get_metric "$CONTEXT1" "running_pods" || echo "0")
RUNNING2=$(get_metric "$CONTEXT2" "running_pods" || echo "0")

FAILED1=$(get_metric "$CONTEXT1" "failed_pods" || echo "0")
FAILED2=$(get_metric "$CONTEXT2" "failed_pods" || echo "0")

SUCCEEDED1=$(get_metric "$CONTEXT1" "succeeded_pods" || echo "0")
SUCCEEDED2=$(get_metric "$CONTEXT2" "succeeded_pods" || echo "0")

UNKNOWN1=$(get_metric "$CONTEXT1" "unknown_pods" || echo "0")
UNKNOWN2=$(get_metric "$CONTEXT2" "unknown_pods" || echo "0")

CONTAINER_CREATING1=$(get_metric "$CONTEXT1" "container_creating" || echo "0")
CONTAINER_CREATING2=$(get_metric "$CONTEXT2" "container_creating" || echo "0")

CRASH_LOOP1=$(get_metric "$CONTEXT1" "crash_loop_backoff" || echo "0")
CRASH_LOOP2=$(get_metric "$CONTEXT2" "crash_loop_backoff" || echo "0")

IMAGE_PULL1=$(get_metric "$CONTEXT1" "image_pull_backoff" || echo "0")
IMAGE_PULL2=$(get_metric "$CONTEXT2" "image_pull_backoff" || echo "0")

POD_INIT1=$(get_metric "$CONTEXT1" "pod_initializing" || echo "0")
POD_INIT2=$(get_metric "$CONTEXT2" "pod_initializing" || echo "0")

TOTAL_PODS1=$(get_metric "$CONTEXT1" "total_pods" || echo "0")
TOTAL_PODS2=$(get_metric "$CONTEXT2" "total_pods" || echo "0")

# Ensure all values are numeric (default to 0 if empty)
PENDING1=${PENDING1:-0}
PENDING2=${PENDING2:-0}
RUNNING1=${RUNNING1:-0}
RUNNING2=${RUNNING2:-0}
FAILED1=${FAILED1:-0}
FAILED2=${FAILED2:-0}
SUCCEEDED1=${SUCCEEDED1:-0}
SUCCEEDED2=${SUCCEEDED2:-0}
UNKNOWN1=${UNKNOWN1:-0}
UNKNOWN2=${UNKNOWN2:-0}
CONTAINER_CREATING1=${CONTAINER_CREATING1:-0}
CONTAINER_CREATING2=${CONTAINER_CREATING2:-0}
CRASH_LOOP1=${CRASH_LOOP1:-0}
CRASH_LOOP2=${CRASH_LOOP2:-0}
IMAGE_PULL1=${IMAGE_PULL1:-0}
IMAGE_PULL2=${IMAGE_PULL2:-0}
POD_INIT1=${POD_INIT1:-0}
POD_INIT2=${POD_INIT2:-0}
TOTAL_PODS1=${TOTAL_PODS1:-0}
TOTAL_PODS2=${TOTAL_PODS2:-0}

MAX_PODS1=$(get_metric "$CONTEXT1" "max_pods_per_node")
MAX_PODS2=$(get_metric "$CONTEXT2" "max_pods_per_node")

MIN_PODS1=$(get_metric "$CONTEXT1" "min_pods_per_node")
MIN_PODS2=$(get_metric "$CONTEXT2" "min_pods_per_node")

if [ "$NODES_WITH_PODS1" -gt 0 ]; then
    AVG_PODS1=$((SCHEDULED1 / NODES_WITH_PODS1))
else
    AVG_PODS1=0
fi

if [ "$NODES_WITH_PODS2" -gt 0 ]; then
    AVG_PODS2=$((SCHEDULED2 / NODES_WITH_PODS2))
else
    AVG_PODS2=0
fi

AVG_CPU1=$(get_metric "$CONTEXT1" "avg_cpu")
AVG_CPU2=$(get_metric "$CONTEXT2" "avg_cpu")

AVG_MEM1=$(get_metric "$CONTEXT1" "avg_mem")
AVG_MEM2=$(get_metric "$CONTEXT2" "avg_mem")

TOTAL_CPU_CAPACITY1=$(get_metric "$CONTEXT1" "total_cpu_capacity")
TOTAL_CPU_CAPACITY2=$(get_metric "$CONTEXT2" "total_cpu_capacity")

TOTAL_MEM_CAPACITY1=$(get_metric "$CONTEXT1" "total_memory_capacity")
TOTAL_MEM_CAPACITY2=$(get_metric "$CONTEXT2" "total_memory_capacity")

TOTAL_CPU_ALLOCATABLE1=$(get_metric "$CONTEXT1" "total_cpu_allocatable")
TOTAL_CPU_ALLOCATABLE2=$(get_metric "$CONTEXT2" "total_cpu_allocatable")

TOTAL_MEM_ALLOCATABLE1=$(get_metric "$CONTEXT1" "total_memory_allocatable")
TOTAL_MEM_ALLOCATABLE2=$(get_metric "$CONTEXT2" "total_memory_allocatable")

# Ensure values are set (default to 0 if empty)
TOTAL_CPU_CAPACITY1=${TOTAL_CPU_CAPACITY1:-0}
TOTAL_CPU_CAPACITY2=${TOTAL_CPU_CAPACITY2:-0}
TOTAL_MEM_CAPACITY1=${TOTAL_MEM_CAPACITY1:-0}
TOTAL_MEM_CAPACITY2=${TOTAL_MEM_CAPACITY2:-0}
TOTAL_CPU_ALLOCATABLE1=${TOTAL_CPU_ALLOCATABLE1:-0}
TOTAL_CPU_ALLOCATABLE2=${TOTAL_CPU_ALLOCATABLE2:-0}
TOTAL_MEM_ALLOCATABLE1=${TOTAL_MEM_ALLOCATABLE1:-0}
TOTAL_MEM_ALLOCATABLE2=${TOTAL_MEM_ALLOCATABLE2:-0}

# Calculate differences
DIFF_NODES_AVAILABLE=$((NODES_AVAILABLE2 - NODES_AVAILABLE1))
DIFF_SCHEDULED=$((SCHEDULED2 - SCHEDULED1))
DIFF_PENDING=$((PENDING2 - PENDING1))
DIFF_AVG_PODS=$((AVG_PODS2 - AVG_PODS1))

# Print comparison table
printf "%-35s | %-25s | %-25s | %-15s\n" "Metric" "$CONTEXT1" "$CONTEXT2" "Difference"
echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────────"

printf "%-35s | %-25s | %-25s | %-15s\n" "Total Nodes" "$NODES1" "$NODES2" ""
printf "%-35s | %-25s | %-25s | %-15s\n" "Total CPU Capacity (cores)" "${TOTAL_CPU_CAPACITY1}" "${TOTAL_CPU_CAPACITY2}" ""
printf "%-35s | %-25s | %-25s | %-15s\n" "Total Memory Capacity (Gi)" "${TOTAL_MEM_CAPACITY1}" "${TOTAL_MEM_CAPACITY2}" ""
printf "%-35s | %-25s | %-25s | %-15s\n" "CPU Allocatable (cores)" "${TOTAL_CPU_ALLOCATABLE1}" "${TOTAL_CPU_ALLOCATABLE2}" ""
printf "%-35s | %-25s | %-25s | %-15s\n" "Memory Allocatable (Gi)" "${TOTAL_MEM_ALLOCATABLE1}" "${TOTAL_MEM_ALLOCATABLE2}" ""
printf "%-35s | %-25s | %-25s | %-15s\n" "Nodes with Pods" "$NODES_WITH_PODS1" "$NODES_WITH_PODS2" ""
if [ "$DIFF_NODES_AVAILABLE" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "Nodes Available" "$NODES_AVAILABLE1" "$NODES_AVAILABLE2" "+$DIFF_NODES_AVAILABLE ✅"
elif [ "$DIFF_NODES_AVAILABLE" -lt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "Nodes Available" "$NODES_AVAILABLE1" "$NODES_AVAILABLE2" "$DIFF_NODES_AVAILABLE"
else
    printf "%-35s | %-25s | %-25s | %-15s\n" "Nodes Available" "$NODES_AVAILABLE1" "$NODES_AVAILABLE2" "0"
fi

echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────────"

if [ "$DIFF_SCHEDULED" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "Scheduled Pods (All Namespaces)" "$SCHEDULED1" "$SCHEDULED2" "+$DIFF_SCHEDULED ✅"
elif [ "$DIFF_SCHEDULED" -lt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "Total Pods (All Namespaces)" "$TOTAL_PODS1" "$TOTAL_PODS2" ""
    printf "%-35s | %-25s | %-25s | %-15s\n" "Scheduled Pods" "$SCHEDULED1" "$SCHEDULED2" "$DIFF_SCHEDULED"
    echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────────"
    printf "%-35s | %-25s | %-25s | %-15s\n" "Pod Status Breakdown:" "" "" ""
    printf "%-35s | %-25s | %-25s | %-15s\n" "  Running Pods" "$RUNNING1" "$RUNNING2" ""
    printf "%-35s | %-25s | %-25s | %-15s\n" "  Pending Pods" "$PENDING1" "$PENDING2" ""
else
    printf "%-35s | %-25s | %-25s | %-15s\n" "Scheduled Pods" "$SCHEDULED1" "$SCHEDULED2" "0"
    echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────────"
    printf "%-35s | %-25s | %-25s | %-15s\n" "Pod Status Breakdown:" "" "" ""
    printf "%-35s | %-25s | %-25s | %-15s\n" "  Running Pods" "$RUNNING1" "$RUNNING2" ""
    printf "%-35s | %-25s | %-25s | %-15s\n" "  Pending Pods" "$PENDING1" "$PENDING2" ""
fi

if [ "$DIFF_PENDING" -lt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "Pending Pods" "$PENDING1" "$PENDING2" "$DIFF_PENDING ✅"
elif [ "$DIFF_PENDING" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "Pending Pods" "$PENDING1" "$PENDING2" "+$DIFF_PENDING"
else
    printf "%-35s | %-25s | %-25s | %-15s\n" "Pending Pods" "$PENDING1" "$PENDING2" "0"
fi

# Show additional pod states if any exist
if [ "${FAILED1:-0}" -gt 0 ] || [ "${FAILED2:-0}" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "  Failed Pods" "${FAILED1:-0}" "${FAILED2:-0}" ""
fi
if [ "${SUCCEEDED1:-0}" -gt 0 ] || [ "${SUCCEEDED2:-0}" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "  Succeeded Pods" "${SUCCEEDED1:-0}" "${SUCCEEDED2:-0}" ""
fi
if [ "${UNKNOWN1:-0}" -gt 0 ] || [ "${UNKNOWN2:-0}" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "  Unknown Pods" "${UNKNOWN1:-0}" "${UNKNOWN2:-0}" ""
fi
if [ "${CONTAINER_CREATING1:-0}" -gt 0 ] || [ "${CONTAINER_CREATING2:-0}" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "  ContainerCreating" "${CONTAINER_CREATING1:-0}" "${CONTAINER_CREATING2:-0}" ""
fi
if [ "${CRASH_LOOP1:-0}" -gt 0 ] || [ "${CRASH_LOOP2:-0}" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "  CrashLoopBackOff" "${CRASH_LOOP1:-0}" "${CRASH_LOOP2:-0}" ""
fi
if [ "${IMAGE_PULL1:-0}" -gt 0 ] || [ "${IMAGE_PULL2:-0}" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "  ImagePullBackOff" "${IMAGE_PULL1:-0}" "${IMAGE_PULL2:-0}" ""
fi
if [ "${POD_INIT1:-0}" -gt 0 ] || [ "${POD_INIT2:-0}" -gt 0 ]; then
    printf "%-35s | %-25s | %-25s | %-15s\n" "  PodInitializing" "${POD_INIT1:-0}" "${POD_INIT2:-0}" ""
fi

echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────────"

printf "%-35s | %-25s | %-25s | %-15s\n" "Avg Pods per Node" "$AVG_PODS1" "$AVG_PODS2" ""
printf "%-35s | %-25s | %-25s | %-15s\n" "Min Pods per Node" "$MIN_PODS1" "$MIN_PODS2" ""
printf "%-35s | %-25s | %-25s | %-15s\n" "Max Pods per Node" "$MAX_PODS1" "$MAX_PODS2" ""

if [ "$MIN_PODS1" -gt 0 ] && [ "$MIN_PODS2" -gt 0 ]; then
    RATIO1=$(echo "scale=2; $MAX_PODS1 / $MIN_PODS1" | bc 2>/dev/null || echo "N/A")
    RATIO2=$(echo "scale=2; $MAX_PODS2 / $MIN_PODS2" | bc 2>/dev/null || echo "N/A")
    printf "%-35s | %-25s | %-25s | %-15s\n" "Distribution Ratio (Max/Min)" "$RATIO1" "$RATIO2" ""
fi

echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────────"

printf "%-35s | %-25s | %-25s | %-15s\n" "Avg CPU Utilization" "$AVG_CPU1" "$AVG_CPU2" ""
printf "%-35s | %-25s | %-25s | %-15s\n" "Avg Memory Utilization" "$AVG_MEM1" "$AVG_MEM2" ""

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Test Workload Pod Status"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Count test workload pods by type
    echo "Test Workload Pods by Type:"
    echo ""
    
    for workload in "test-workload-small" "test-workload-medium" "test-workload-large"; do
        COUNT1=$(kubectl get pods --all-namespaces --context "$CONTEXT1" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items | length' | tr -d ' ' || echo "0")
        COUNT2=$(kubectl get pods --all-namespaces --context "$CONTEXT2" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items | length' | tr -d ' ' || echo "0")
        
        RUNNING1=$(kubectl get pods --all-namespaces --context "$CONTEXT1" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l | tr -d ' ' || echo "0")
        RUNNING2=$(kubectl get pods --all-namespaces --context "$CONTEXT2" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l | tr -d ' ' || echo "0")
        
        PENDING1=$(kubectl get pods --all-namespaces --context "$CONTEXT1" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ' || echo "0")
        PENDING2=$(kubectl get pods --all-namespaces --context "$CONTEXT2" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ' || echo "0")
        
        WORKLOAD_NAME=$(echo "$workload" | sed 's/test-workload-//')
        echo "  $WORKLOAD_NAME:"
        echo "    $CONTEXT1: Total=$COUNT1, Running=$RUNNING1, Pending=$PENDING1"
        echo "    $CONTEXT2: Total=$COUNT2, Running=$RUNNING2, Pending=$PENDING2"
        echo ""
    done
    
    echo "════════════════════════════════════════════════════════════════"
    echo "  Pod Scheduling Status (All Pods)"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Show pending pods for both clusters
    PENDING1=$(get_metric "$CONTEXT1" "pending_pods")
    PENDING2=$(get_metric "$CONTEXT2" "pending_pods")
    
    echo "Pod Status Breakdown:"
    echo "  Total Pods:"
    echo "    $CONTEXT1: $TOTAL_PODS1"
    echo "    $CONTEXT2: $TOTAL_PODS2"
    echo ""
    echo "  By Status:"
    echo "    Running:"
    echo "      $CONTEXT1: $RUNNING1"
    echo "      $CONTEXT2: $RUNNING2"
    echo ""
    echo "    Pending (not yet scheduled):"
    echo "      $CONTEXT1: $PENDING1"
    echo "      $CONTEXT2: $PENDING2"
    if [ "${FAILED1:-0}" -gt 0 ] || [ "${FAILED2:-0}" -gt 0 ]; then
        echo ""
        echo "    Failed:"
        echo "      $CONTEXT1: ${FAILED1:-0}"
        echo "      $CONTEXT2: ${FAILED2:-0}"
    fi
    if [ "${SUCCEEDED1:-0}" -gt 0 ] || [ "${SUCCEEDED2:-0}" -gt 0 ]; then
        echo ""
        echo "    Succeeded (completed):"
        echo "      $CONTEXT1: ${SUCCEEDED1:-0}"
        echo "      $CONTEXT2: ${SUCCEEDED2:-0}"
    fi
    if [ "${UNKNOWN1:-0}" -gt 0 ] || [ "${UNKNOWN2:-0}" -gt 0 ]; then
        echo ""
        echo "    Unknown:"
        echo "      $CONTEXT1: ${UNKNOWN1:-0}"
        echo "      $CONTEXT2: ${UNKNOWN2:-0}"
    fi
    if [ "${CONTAINER_CREATING1:-0}" -gt 0 ] || [ "${CONTAINER_CREATING2:-0}" -gt 0 ]; then
        echo ""
        echo "    ContainerCreating (starting up):"
        echo "      $CONTEXT1: ${CONTAINER_CREATING1:-0}"
        echo "      $CONTEXT2: ${CONTAINER_CREATING2:-0}"
    fi
    if [ "${CRASH_LOOP1:-0}" -gt 0 ] || [ "${CRASH_LOOP2:-0}" -gt 0 ]; then
        echo ""
        echo "    CrashLoopBackOff (crashing):"
        echo "      $CONTEXT1: ${CRASH_LOOP1:-0}"
        echo "      $CONTEXT2: ${CRASH_LOOP2:-0}"
    fi
    if [ "${IMAGE_PULL1:-0}" -gt 0 ] || [ "${IMAGE_PULL2:-0}" -gt 0 ]; then
        echo ""
        echo "    ImagePullBackOff (image pull failed):"
        echo "      $CONTEXT1: ${IMAGE_PULL1:-0}"
        echo "      $CONTEXT2: ${IMAGE_PULL2:-0}"
    fi
    if [ "${POD_INIT1:-0}" -gt 0 ] || [ "${POD_INIT2:-0}" -gt 0 ]; then
        echo ""
        echo "    PodInitializing (init containers running):"
        echo "      $CONTEXT1: ${POD_INIT1:-0}"
        echo "      $CONTEXT2: ${POD_INIT2:-0}"
    fi
    echo ""
    
    # Check if there's a difference in total pods
    if [ "$TOTAL_PODS1" -ne "$TOTAL_PODS2" ]; then
        DIFF_TOTAL=$((TOTAL_PODS2 - TOTAL_PODS1))
        echo "💡 Why different total pod counts?"
        echo ""
        echo "  Cluster A has $TOTAL_PODS1 total pods"
        echo "  Cluster B has $TOTAL_PODS2 total pods"
        echo "  Difference: $DIFF_TOTAL pods"
        echo ""
        echo "  This could mean:"
        echo "    • Some deployments didn't create all replicas in Cluster A"
        echo "    • Some pods failed to start in Cluster A"
        echo "    • Resource constraints prevented pod creation"
        echo ""
        echo "  Check deployment status:"
        echo "    kubectl get deployments -A --context $CONTEXT1"
        echo "    kubectl get deployments -A --context $CONTEXT2"
        echo ""
        if [ "${FAILED1:-0}" -gt 0 ]; then
            echo "  Check failed pods in Cluster A:"
            echo "    kubectl get pods -A --context $CONTEXT1 --field-selector=status.phase=Failed"
            echo ""
        fi
    fi
    
    echo "Note: Pod counts include ALL namespaces:"
    echo "  • Test workloads you deployed"
    echo "  • Prometheus stack pods"
    echo "  • System pods (kube-system, etc.)"
    echo "  • Metrics-server pods"
    echo ""
    
    if [ "$PENDING1" -gt 0 ] || [ "$PENDING2" -gt 0 ]; then
        echo "💡 Why fewer scheduled pods?"
        echo ""
        if [ "$PENDING1" -gt "$PENDING2" ]; then
            DIFF=$((PENDING1 - PENDING2))
            echo "  → $CONTEXT1 has $DIFF more pending pods than $CONTEXT2"
            echo "  → This explains why it shows fewer scheduled pods"
            echo ""
            echo "  Common reasons for pending pods:"
            echo "    • Insufficient resources (CPU/Memory) on nodes"
            echo "    • Scheduler can't find suitable nodes"
            echo "    • Bin packing packs more efficiently, leaving less room"
            echo "    • Default scheduler spreads pods, using nodes less efficiently"
        elif [ "$PENDING2" -gt "$PENDING1" ]; then
            DIFF=$((PENDING2 - PENDING1))
            echo "  → $CONTEXT2 has $DIFF more pending pods than $CONTEXT1"
        else
            echo "  → Both clusters have pending pods"
        fi
        echo ""
        echo "  To see why pods are pending:"
        echo "    kubectl get pods -A --context $CONTEXT1 --field-selector=status.phase=Pending"
        echo "    kubectl get pods -A --context $CONTEXT2 --field-selector=status.phase=Pending"
        echo ""
    fi
    
    echo "════════════════════════════════════════════════════════════════"
    echo "  Key Takeaways"
    echo "════════════════════════════════════════════════════════════════"
    echo ""

# Generate insights
if [ "$DIFF_NODES_AVAILABLE" -gt 0 ]; then
    echo "✅ Cluster B has $DIFF_NODES_AVAILABLE more available node(s)"
    echo "   → Better capacity for scaling"
fi

if [ "$DIFF_SCHEDULED" -gt 0 ]; then
    PERCENT=$(echo "scale=1; ($DIFF_SCHEDULED * 100) / $SCHEDULED1" | bc 2>/dev/null || echo "0")
    echo "✅ Cluster B has $DIFF_SCHEDULED more scheduled pods (+${PERCENT}%)"
    echo "   → Better workload density"
fi

if [ "$DIFF_PENDING" -lt 0 ]; then
    echo "✅ Cluster B has $((DIFF_PENDING * -1)) fewer pending pods"
    echo "   → Better scheduling efficiency"
fi

if [ "$AVG_PODS2" -gt "$AVG_PODS1" ]; then
    echo "✅ Cluster B has higher average pods per node ($AVG_PODS2 vs $AVG_PODS1)"
    echo "   → Better resource utilization"
fi

if [ -n "$RATIO1" ] && [ -n "$RATIO2" ] && [ "$RATIO1" != "N/A" ] && [ "$RATIO2" != "N/A" ]; then
    RATIO1_NUM=$(echo "$RATIO1" | cut -d. -f1)
    RATIO2_NUM=$(echo "$RATIO2" | cut -d. -f1)
    if [ "$RATIO2_NUM" -gt "$RATIO1_NUM" ]; then
        echo "✅ Cluster B has higher distribution variance (ratio: $RATIO2 vs $RATIO1)"
        echo "   → Indicates bin packing is working (pods more concentrated)"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Comparison Complete"
echo "════════════════════════════════════════════════════════════════"
echo ""
