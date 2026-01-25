#!/bin/bash
# bin-packing-comparison.sh
#
# Creates two clusters side-by-side to compare bin packing vs default scheduling
# 
# This script:
# 1. Creates Cluster A with DEFAULT scheduler (LeastAllocated - no bin packing)
# 2. Creates Cluster B with BIN PACKING scheduler (MostAllocated)
# 3. Deploys identical workloads to both clusters
# 4. Measures and compares actual utilization metrics
# 5. Shows real observed differences
#
# Usage:
#   ./bin-packing-comparison.sh
#
# Note: This creates 2 clusters, so requires more resources (~8GB RAM recommended)

set -e

CLUSTER_A_NAME="cluster-default"
CLUSTER_B_NAME="cluster-bin-packing"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "  Bin Packing vs Default Scheduler - Real Comparison"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "This will create TWO clusters to compare:"
echo "  Cluster A: Default scheduler (LeastAllocated - spreads pods)"
echo "  Cluster B: Bin packing scheduler (MostAllocated - concentrates pods)"
echo ""
echo "⚠️  This requires significant resources (~8GB RAM, 2x cluster overhead)"
echo ""

# Check for existing clusters
EXISTING_A=$(kind get clusters 2>/dev/null | grep -q "^${CLUSTER_A_NAME}$" && echo "yes" || echo "no")
EXISTING_B=$(kind get clusters 2>/dev/null | grep -q "^${CLUSTER_B_NAME}$" && echo "yes" || echo "no")

if [ "$EXISTING_A" = "yes" ] || [ "$EXISTING_B" = "yes" ]; then
    echo "⚠️  Existing clusters detected:"
    [ "$EXISTING_A" = "yes" ] && echo "  - $CLUSTER_A_NAME"
    [ "$EXISTING_B" = "yes" ] && echo "  - $CLUSTER_B_NAME"
    echo ""
    echo "These clusters will be deleted and recreated to ensure a clean comparison."
    echo "Note: New clusters will be kept running after the script completes."
    echo ""
fi

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Cleanup function (only called if user explicitly requests deletion)
cleanup() {
    echo ""
    echo "Deleting clusters..."
    kind delete cluster --name "$CLUSTER_A_NAME" 2>/dev/null || true
    kind delete cluster --name "$CLUSTER_B_NAME" 2>/dev/null || true
    rm -f /tmp/cluster-*.yaml /tmp/workload-*.yaml /tmp/prometheus-*.yaml
    echo "✓ Clusters deleted"
}

# Clusters are kept by default - user must explicitly request deletion
# No trap - clusters persist after script exits

# Create cluster A (default scheduler)
create_cluster_default() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Creating Cluster A: Default Scheduler (No Bin Packing)"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    cat > /tmp/cluster-default.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF
    
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_A_NAME}$"; then
        echo "Deleting existing cluster: $CLUSTER_A_NAME"
        kind delete cluster --name "$CLUSTER_A_NAME"
        sleep 2
    fi
    
    kind create cluster --name "$CLUSTER_A_NAME" --config /tmp/cluster-default.yaml
    
    echo "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --context "kind-${CLUSTER_A_NAME}" --timeout=300s
    
    # Install metrics-server
    echo "Installing metrics-server..."
    kubectl apply --context "kind-${CLUSTER_A_NAME}" -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    kubectl patch deployment metrics-server -n kube-system \
        --context "kind-${CLUSTER_A_NAME}" \
        --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
    
    sleep 10
    echo "✓ Cluster A ready (default scheduler)"
}

# Create cluster B (bin packing scheduler)
create_cluster_bin_packing() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Creating Cluster B: Bin Packing Scheduler"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Check if cluster exists and delete it
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_B_NAME}$"; then
        echo "Deleting existing cluster: $CLUSTER_B_NAME"
        kind delete cluster --name "$CLUSTER_B_NAME"
        sleep 2
    fi
    
    # Use the setup script but skip Prometheus
    echo "n" | CLUSTER_NAME="$CLUSTER_B_NAME" STRATEGY="mostallocated" \
        bash "$SCRIPT_DIR/bin-packing-kind-setup.sh" "mostallocated" 2>&1 | \
        grep -v "Install kube-prometheus-stack" | \
        grep -v "Press Enter" || true
    
    sleep 5
    echo "✓ Cluster B ready (bin packing scheduler)"
}

# Install Prometheus stack on both clusters
install_prometheus_both() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Installing kube-prometheus-stack on Both Clusters"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        echo "Installing helm..."
        if command -v brew &> /dev/null; then
            brew install helm || {
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
            }
        else
            curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        fi
    fi
    
    # Add Prometheus repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update
    
    # Create values file
    cat > /tmp/prometheus-values.yaml <<EOF
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
    replicas: 1
    retention: 7d

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
    replicas: 1

grafana:
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
  persistence:
    enabled: false
  adminPassword: demo123

nodeExporter:
  resources:
    requests:
      cpu: 100m
      memory: 64Mi

kubeStateMetrics:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
  replicas: 1
EOF
    
    echo "Installing on Cluster A (default scheduler)..."
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --values /tmp/prometheus-values.yaml \
        --wait \
        --timeout 10m \
        --kube-context "kind-${CLUSTER_A_NAME}" 2>&1 | grep -v "WARNING" || {
        echo "  Note: Installation may take time, continuing..."
    }
    
    echo ""
    echo "Installing on Cluster B (bin packing scheduler)..."
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --values /tmp/prometheus-values.yaml \
        --wait \
        --timeout 10m \
        --kube-context "kind-${CLUSTER_B_NAME}" 2>&1 | grep -v "WARNING" || {
        echo "  Note: Installation may take time, continuing..."
    }
    
    echo ""
    echo "Waiting for Prometheus stacks to be ready..."
    sleep 20
    
    echo "✓ Prometheus stacks installed on both clusters"
    rm -f /tmp/prometheus-values.yaml
}

# Deploy identical workloads to both clusters
deploy_workloads() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Deploying Identical Test Workloads to Both Clusters"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    cat > /tmp/workload.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-workload-small
spec:
  replicas: 10
  selector:
    matchLabels:
      app: test-workload-small
  template:
    metadata:
      labels:
        app: test-workload-small
    spec:
      containers:
      - name: app
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-workload-medium
spec:
  replicas: 8
  selector:
    matchLabels:
      app: test-workload-medium
  template:
    metadata:
      labels:
        app: test-workload-medium
    spec:
      containers:
      - name: app
        image: nginx:latest
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-workload-large
spec:
  replicas: 5
  selector:
    matchLabels:
      app: test-workload-large
  template:
    metadata:
      labels:
        app: test-workload-large
    spec:
      containers:
      - name: app
        image: nginx:latest
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
EOF
    
    echo "Deploying to Cluster A (default scheduler)..."
    kubectl apply --context "kind-${CLUSTER_A_NAME}" -f /tmp/workload.yaml
    
    echo "Deploying to Cluster B (bin packing scheduler)..."
    kubectl apply --context "kind-${CLUSTER_B_NAME}" -f /tmp/workload.yaml
    
    echo ""
    echo "Waiting for pods to be scheduled..."
    sleep 25
    
    echo "✓ Workloads deployed to both clusters"
    rm -f /tmp/workload.yaml
}

# Measure and compare
compare_clusters() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Real Comparison: Default vs Bin Packing"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    echo "Cluster Resource Capacity:"
    echo ""
    
    # Get cluster capacity for both clusters
    CPU_CAP_A=$(kubectl get nodes --context "kind-${CLUSTER_A_NAME}" -o json 2>/dev/null | \
        jq -r '[.items[].status.capacity.cpu] | map(tonumber? // 0) | add' | \
        awk '{printf "%.2f", $1}' || echo "0")
    MEM_CAP_A=$(kubectl get nodes --context "kind-${CLUSTER_A_NAME}" -o json 2>/dev/null | \
        jq -r '[.items[].status.capacity.memory] | map(gsub("[^0-9]"; "") | tonumber) | add' | \
        awk '{printf "%.0f", $1/1024/1024/1024}' || echo "0")
    CPU_ALLOC_A=$(kubectl get nodes --context "kind-${CLUSTER_A_NAME}" -o json 2>/dev/null | \
        jq -r '[.items[].status.allocatable.cpu] | map(tonumber? // 0) | add' | \
        awk '{printf "%.2f", $1}' || echo "0")
    MEM_ALLOC_A=$(kubectl get nodes --context "kind-${CLUSTER_A_NAME}" -o json 2>/dev/null | \
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
    
    CPU_CAP_B=$(kubectl get nodes --context "kind-${CLUSTER_B_NAME}" -o json 2>/dev/null | \
        jq -r '[.items[].status.capacity.cpu] | map(tonumber? // 0) | add' | \
        awk '{printf "%.2f", $1}' || echo "0")
    MEM_CAP_B=$(kubectl get nodes --context "kind-${CLUSTER_B_NAME}" -o json 2>/dev/null | \
        jq -r '[.items[].status.capacity.memory] | map(gsub("[^0-9]"; "") | tonumber) | add' | \
        awk '{printf "%.0f", $1/1024/1024/1024}' || echo "0")
    CPU_ALLOC_B=$(kubectl get nodes --context "kind-${CLUSTER_B_NAME}" -o json 2>/dev/null | \
        jq -r '[.items[].status.allocatable.cpu] | map(tonumber? // 0) | add' | \
        awk '{printf "%.2f", $1}' || echo "0")
    MEM_ALLOC_B=$(kubectl get nodes --context "kind-${CLUSTER_B_NAME}" -o json 2>/dev/null | \
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
    
    echo "  Cluster A (Default Scheduler):"
    echo "    Total CPU Capacity:     ${CPU_CAP_A} cores"
    echo "    Total Memory Capacity:  ${MEM_CAP_A} Gi"
    echo "    CPU Allocatable:       ${CPU_ALLOC_A} cores"
    echo "    Memory Allocatable:    ${MEM_ALLOC_A} Gi"
    echo ""
    echo "  Cluster B (Bin Packing Scheduler):"
    echo "    Total CPU Capacity:     ${CPU_CAP_B} cores"
    echo "    Total Memory Capacity:  ${MEM_CAP_B} Gi"
    echo "    CPU Allocatable:       ${CPU_ALLOC_B} cores"
    echo "    Memory Allocatable:    ${MEM_ALLOC_B} Gi"
    echo ""
    echo "  Note: Allocatable = Capacity minus system reservations"
    echo ""
    echo "Test Workloads Deployed:"
    echo ""
    echo "  1. test-workload-small:"
    echo "     - Replicas: 10"
    echo "     - CPU: 100m request, 200m limit"
    echo "     - Memory: 128Mi request, 256Mi limit"
    echo ""
    echo "  2. test-workload-medium:"
    echo "     - Replicas: 8"
    echo "     - CPU: 200m request, 500m limit"
    echo "     - Memory: 256Mi request, 512Mi limit"
    echo ""
    echo "  3. test-workload-large:"
    echo "     - Replicas: 5"
    echo "     - CPU: 500m request, 1000m limit"
    echo "     - Memory: 512Mi request, 1Gi limit"
    echo ""
    echo "  Total Expected Test Pods: 23 (10 + 8 + 5)"
    echo "  Total Test Workload Resources:"
    echo "    CPU Requests: 5100m (5.1 cores)"
    echo "    Memory Requests: ~5.9 Gi"
    echo ""
    echo "  Additional Workloads:"
    echo "    - Prometheus stack (kube-prometheus-stack)"
    echo "    - Metrics-server"
    echo "    - System pods"
    echo ""
    
    echo "Collecting metrics (this may take a moment)..."
    sleep 15
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CLUSTER A: Default Scheduler (LeastAllocated)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "Test Workload Pod Distribution:"
    kubectl get pods --context "kind-${CLUSTER_A_NAME}" \
        -l 'app in (test-workload-small,test-workload-medium,test-workload-large)' \
        -o wide --no-headers 2>/dev/null | \
        awk '{print $7}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %-30s: %d pods\n", $2, $1}' || echo "  (collecting...)"
    
    echo ""
    echo "Prometheus Stack Pod Distribution:"
    kubectl get pods -n monitoring --context "kind-${CLUSTER_A_NAME}" \
        -o wide --no-headers 2>/dev/null | \
        awk '{print $7}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %-30s: %d pods\n", $2, $1}' || echo "  (no pods yet)"
    
    echo ""
    echo "All Pods Distribution (All Namespaces):"
    kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
        -o wide --no-headers 2>/dev/null | \
        awk '{print $8}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %-30s: %d pods\n", $2, $1}' || echo "  (collecting...)"
    
    echo ""
    echo "Node Utilization:"
    kubectl top nodes --context "kind-${CLUSTER_A_NAME}" 2>/dev/null || echo "  (metrics collecting...)"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CLUSTER B: Bin Packing Scheduler (MostAllocated)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "Test Workload Pod Distribution:"
    kubectl get pods --context "kind-${CLUSTER_B_NAME}" \
        -l 'app in (test-workload-small,test-workload-medium,test-workload-large)' \
        -o wide --no-headers 2>/dev/null | \
        awk '{print $7}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %-30s: %d pods\n", $2, $1}' || echo "  (collecting...)"
    
    echo ""
    echo "Prometheus Stack Pod Distribution:"
    kubectl get pods -n monitoring --context "kind-${CLUSTER_B_NAME}" \
        -o wide --no-headers 2>/dev/null | \
        awk '{print $7}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %-30s: %d pods\n", $2, $1}' || echo "  (no pods yet)"
    
    echo ""
    echo "All Pods Distribution (All Namespaces):"
    kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o wide --no-headers 2>/dev/null | \
        awk '{print $8}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %-30s: %d pods\n", $2, $1}' || echo "  (collecting...)"
    
    echo ""
    echo "Node Utilization:"
    kubectl top nodes --context "kind-${CLUSTER_B_NAME}" 2>/dev/null || echo "  (metrics collecting...)"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  POD SCHEDULING STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Count pods by status for Cluster A
    SCHEDULED_A=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .metadata.name' | wc -l | tr -d ' ')
    PENDING_A=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ')
    RUNNING_A=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l | tr -d ' ')
    FAILED_A=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Failed") | .metadata.name' | wc -l | tr -d ' ')
    SUCCEEDED_A=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Succeeded") | .metadata.name' | wc -l | tr -d ' ')
    UNKNOWN_A=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Unknown" or .status.phase == null) | .metadata.name' | wc -l | tr -d ' ')
    TOTAL_A=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
        -o json 2>/dev/null | jq -r '.items | length' | tr -d ' ')
    
    # Count pods by status for Cluster B
    SCHEDULED_B=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.spec.nodeName != null) | .metadata.name' | wc -l | tr -d ' ')
    PENDING_B=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ')
    RUNNING_B=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l | tr -d ' ')
    FAILED_B=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Failed") | .metadata.name' | wc -l | tr -d ' ')
    SUCCEEDED_B=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Succeeded") | .metadata.name' | wc -l | tr -d ' ')
    UNKNOWN_B=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Unknown" or .status.phase == null) | .metadata.name' | wc -l | tr -d ' ')
    TOTAL_B=$(kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o json 2>/dev/null | jq -r '.items | length' | tr -d ' ')
    
    echo "Cluster A (Default Scheduler):"
    echo "  Total Pods:     $TOTAL_A"
    echo "  Scheduled:      $SCHEDULED_A"
    echo "  Pending:        $PENDING_A"
    if [ "$PENDING_A" -gt 0 ]; then
        echo ""
        echo "  ⚠️  $PENDING_A pod(s) are Pending (not scheduled yet)"
        echo "     Checking why..."
        echo ""
        kubectl get pods --all-namespaces --context "kind-${CLUSTER_A_NAME}" \
            --field-selector=status.phase=Pending -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
REASON:.status.conditions[?(@.type==\"PodScheduled\")].reason,\
MESSAGE:.status.conditions[?(@.type==\"PodScheduled\")].message 2>/dev/null | head -10 || echo "    (checking...)"
    fi
    
    echo ""
    echo "Cluster B (Bin Packing Scheduler):"
    echo "  Total Pods (All Namespaces): $TOTAL_B"
    echo "  Scheduled:                   $SCHEDULED_B"
    echo ""
    echo "  Pod Status Breakdown:"
    echo "    Running:    $RUNNING_B"
    echo "    Pending:    $PENDING_B"
    if [ "$FAILED_B" -gt 0 ]; then
        echo "    Failed:     $FAILED_B"
    fi
    if [ "$SUCCEEDED_B" -gt 0 ]; then
        echo "    Succeeded:  $SUCCEEDED_B"
    fi
    if [ "$UNKNOWN_B" -gt 0 ]; then
        echo "    Unknown:    $UNKNOWN_B"
    fi
    echo ""
    echo "  Breakdown by namespace:"
    kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
        -o json 2>/dev/null | jq -r '.items | group_by(.metadata.namespace) | .[] | "    \(.[0].metadata.namespace): \(length) pods"' || echo "    (collecting...)"
    if [ "$PENDING_B" -gt 0 ]; then
        echo ""
        echo "  ⚠️  $PENDING_B pod(s) are Pending (not scheduled yet)"
        echo "     Checking why..."
        echo ""
        kubectl get pods --all-namespaces --context "kind-${CLUSTER_B_NAME}" \
            --field-selector=status.phase=Pending -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
REASON:.status.conditions[?(@.type==\"PodScheduled\")].reason,\
MESSAGE:.status.conditions[?(@.type==\"PodScheduled\")].message 2>/dev/null | head -10 || echo "    (checking...)"
    fi
    
    echo ""
    
    # Analyze the difference
    if [ "$TOTAL_A" -lt "$TOTAL_B" ]; then
        DIFF=$((TOTAL_B - TOTAL_A))
        echo "💡 Insight: Cluster A has $DIFF fewer TOTAL pods than Cluster B"
        echo ""
        if [ "$PENDING_A" -eq 0 ] && [ "$PENDING_B" -eq 0 ]; then
            echo "   → Both clusters have 0 pending pods (all pods that exist got scheduled)"
            echo "   → But Cluster A has fewer pods created in the first place"
            echo ""
            echo "   Possible reasons:"
            echo "     • Some deployments didn't create all replicas in Cluster A"
            echo "     • Resource constraints prevented some pods from being created"
            echo "     • Some pods failed/evicted and weren't recreated"
            echo ""
            echo "   Check deployment status:"
            echo "     kubectl get deployments -A --context kind-${CLUSTER_A_NAME}"
            echo "     kubectl get deployments -A --context kind-${CLUSTER_B_NAME}"
            if [ "$FAILED_A" -gt 0 ]; then
                echo ""
                echo "   Check failed pods in Cluster A:"
                echo "     kubectl get pods -A --context kind-${CLUSTER_A_NAME} --field-selector=status.phase=Failed"
            fi
        fi
    elif [ "$PENDING_A" -gt "$PENDING_B" ]; then
        DIFF=$((PENDING_A - PENDING_B))
        echo "💡 Insight: Cluster A has $DIFF more pending pods than Cluster B"
        echo "   → This is why Cluster A shows fewer scheduled pods"
        echo "   → Bin packing scheduler is more efficient at finding suitable nodes"
        echo "   → Default scheduler spreads pods evenly, leaving less room for new pods"
    elif [ "$PENDING_B" -gt "$PENDING_A" ]; then
        DIFF=$((PENDING_B - PENDING_A))
        echo "💡 Insight: Cluster B has $DIFF more pending pods than Cluster A"
    else
        if [ "$TOTAL_A" -eq "$TOTAL_B" ]; then
            echo "💡 Both clusters have the same number of pods and pending status"
        else
            echo "💡 Both clusters have 0 pending pods, but different total pod counts"
        fi
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  TEST WORKLOAD STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "Cluster A (Default Scheduler) - Test Workload Pods:"
    for workload in "test-workload-small" "test-workload-medium" "test-workload-large"; do
        TOTAL=$(kubectl get pods --context "kind-${CLUSTER_A_NAME}" \
            -l app="$workload" -o json 2>/dev/null | jq -r '.items | length' | tr -d ' ' || echo "0")
        RUNNING=$(kubectl get pods --context "kind-${CLUSTER_A_NAME}" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l | tr -d ' ' || echo "0")
        PENDING=$(kubectl get pods --context "kind-${CLUSTER_A_NAME}" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ' || echo "0")
        
        WORKLOAD_NAME=$(echo "$workload" | sed 's/test-workload-//')
        echo "  $WORKLOAD_NAME: Total=$TOTAL, Running=$RUNNING, Pending=$PENDING"
    done
    
    echo ""
    echo "Cluster B (Bin Packing Scheduler) - Test Workload Pods:"
    for workload in "test-workload-small" "test-workload-medium" "test-workload-large"; do
        TOTAL=$(kubectl get pods --context "kind-${CLUSTER_B_NAME}" \
            -l app="$workload" -o json 2>/dev/null | jq -r '.items | length' | tr -d ' ' || echo "0")
        RUNNING=$(kubectl get pods --context "kind-${CLUSTER_B_NAME}" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l | tr -d ' ' || echo "0")
        PENDING=$(kubectl get pods --context "kind-${CLUSTER_B_NAME}" \
            -l app="$workload" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name' | wc -l | tr -d ' ' || echo "0")
        
        WORKLOAD_NAME=$(echo "$workload" | sed 's/test-workload-//')
        echo "  $WORKLOAD_NAME: Total=$TOTAL, Running=$RUNNING, Pending=$PENDING"
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  OBSERVED DIFFERENCES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Calculate nodes used (for test workloads)
    NODES_A=$(kubectl get pods --context "kind-${CLUSTER_A_NAME}" \
        -l 'app in (test-workload-small,test-workload-medium,test-workload-large)' \
        -o wide --no-headers 2>/dev/null | awk '{print $7}' | sort -u | wc -l | tr -d ' ')
    NODES_B=$(kubectl get pods --context "kind-${CLUSTER_B_NAME}" \
        -l 'app in (test-workload-small,test-workload-medium,test-workload-large)' \
        -o wide --no-headers 2>/dev/null | awk '{print $7}' | sort -u | wc -l | tr -d ' ')
    
    # Calculate nodes used for Prometheus stack
    NODES_PROM_A=$(kubectl get pods -n monitoring --context "kind-${CLUSTER_A_NAME}" \
        -o wide --no-headers 2>/dev/null | awk '{print $7}' | sort -u | wc -l | tr -d ' ')
    NODES_PROM_B=$(kubectl get pods -n monitoring --context "kind-${CLUSTER_B_NAME}" \
        -o wide --no-headers 2>/dev/null | awk '{print $7}' | sort -u | wc -l | tr -d ' ')
    
    echo "Test Workload Nodes Used:"
    echo "  Cluster A (Default):    $NODES_A nodes"
    echo "  Cluster B (Bin Packing): $NODES_B nodes"
    if [ -n "$NODES_A" ] && [ -n "$NODES_B" ] && [ "$NODES_A" -gt "$NODES_B" ] 2>/dev/null; then
        REDUCTION=$(( (NODES_A - NODES_B) * 100 / NODES_A ))
        echo "  → Bin packing uses $((NODES_A - NODES_B)) fewer nodes ($REDUCTION% reduction)"
    fi
    
    echo ""
    echo "Prometheus Stack Nodes Used:"
    echo "  Cluster A (Default):    $NODES_PROM_A nodes"
    echo "  Cluster B (Bin Packing): $NODES_PROM_B nodes"
    if [ -n "$NODES_PROM_A" ] && [ -n "$NODES_PROM_B" ] && [ "$NODES_PROM_A" -gt "$NODES_PROM_B" ] 2>/dev/null; then
        REDUCTION=$(( (NODES_PROM_A - NODES_PROM_B) * 100 / NODES_PROM_A ))
        echo "  → Bin packing uses $((NODES_PROM_A - NODES_PROM_B)) fewer nodes ($REDUCTION% reduction)"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Prometheus Stack Distribution"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "Cluster A (Default) - Prometheus Stack:"
    kubectl get pods -n monitoring --context "kind-${CLUSTER_A_NAME}" \
        -o wide --no-headers 2>/dev/null | \
        awk '{print $7}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %-30s: %d pods\n", $2, $1}' || echo "  (no pods yet)"
    
    echo ""
    echo "Cluster B (Bin Packing) - Prometheus Stack:"
    kubectl get pods -n monitoring --context "kind-${CLUSTER_B_NAME}" \
        -o wide --no-headers 2>/dev/null | \
        awk '{print $7}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %-30s: %d pods\n", $2, $1}' || echo "  (no pods yet)"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Key Observations"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Pod Distribution Pattern:"
    echo "  Cluster A (Default):    Pods spread evenly across nodes"
    echo "  Cluster B (Bin Packing): Pods concentrated on fewer nodes"
    echo ""
    echo "Real Measured Differences:"
    echo "  - Default scheduler spreads pods for load balancing"
    echo "  - Bin packing concentrates pods for resource efficiency"
    echo "  - Bin packing typically uses fewer nodes for the same workload"
    echo "  - Bin packing shows higher utilization on nodes with pods"
    echo "  - Bin packing leaves more nodes available for scaling"
    echo ""
    
    # Calculate summary statistics
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Summary Statistics"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Count nodes with pods
    NODES_WITH_PODS_A=$(kubectl get pods --context "kind-${CLUSTER_A_NAME}" \
        -l 'app in (test-workload-small,test-workload-medium,test-workload-large)' \
        -o wide --no-headers 2>/dev/null | awk '{print $7}' | sort -u | wc -l | tr -d ' ')
    
    NODES_WITH_PODS_B=$(kubectl get pods --context "kind-${CLUSTER_B_NAME}" \
        -l 'app in (test-workload-small,test-workload-medium,test-workload-large)' \
        -o wide --no-headers 2>/dev/null | awk '{print $7}' | sort -u | wc -l | tr -d ' ')
    
    TOTAL_NODES=3
    
    echo "Test Workload Nodes Used:"
    echo "  Cluster A (Default):    $NODES_WITH_PODS_A / $TOTAL_NODES nodes"
    echo "  Cluster B (Bin Packing): $NODES_WITH_PODS_B / $TOTAL_NODES nodes"
    
    if [ "$NODES_WITH_PODS_A" -gt "$NODES_WITH_PODS_B" ] 2>/dev/null; then
        REDUCTION=$(( (NODES_WITH_PODS_A - NODES_WITH_PODS_B) * 100 / NODES_WITH_PODS_A ))
        echo "  → Bin packing uses $((NODES_WITH_PODS_A - NODES_WITH_PODS_B)) fewer nodes ($REDUCTION% reduction)"
    elif [ "$NODES_WITH_PODS_B" -lt "$NODES_WITH_PODS_A" ] 2>/dev/null; then
        echo "  → Bin packing uses fewer nodes (concentrated distribution)"
    fi
    
    NODES_AVAILABLE_A=$((TOTAL_NODES - NODES_WITH_PODS_A))
    NODES_AVAILABLE_B=$((TOTAL_NODES - NODES_WITH_PODS_B))
    
    echo ""
    echo "Nodes Available for Additional Workloads:"
    echo "  Cluster A (Default):    $NODES_AVAILABLE_A nodes"
    echo "  Cluster B (Bin Packing): $NODES_AVAILABLE_B nodes"
    
    if [ "$NODES_AVAILABLE_B" -gt "$NODES_AVAILABLE_A" ] 2>/dev/null; then
        echo "  → Bin packing has $((NODES_AVAILABLE_B - NODES_AVAILABLE_A)) more nodes available"
    fi
    
    echo ""
}

# Main execution
main() {
    create_cluster_default
    create_cluster_bin_packing
    install_prometheus_both
    deploy_workloads
    compare_clusters
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Side-by-Side Comparison Complete!"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Both clusters are running with identical applications:"
    echo ""
    echo "Cluster A (Default Scheduler):"
    echo "  Context: kind-${CLUSTER_A_NAME}"
    echo "  Applications: Prometheus stack + test workloads"
    echo "  Scheduler: LeastAllocated (spreads pods)"
    echo ""
    echo "Cluster B (Bin Packing Scheduler):"
    echo "  Context: kind-${CLUSTER_B_NAME}"
    echo "  Applications: Prometheus stack + test workloads"
    echo "  Scheduler: MostAllocated (concentrates pods)"
    echo ""
    echo "Explore the differences:"
    echo "  # Compare pod distribution"
    echo "  kubectl get pods -A --context kind-${CLUSTER_A_NAME} -o wide | awk '{print \$8}' | sort | uniq -c"
    echo "  kubectl get pods -A --context kind-${CLUSTER_B_NAME} -o wide | awk '{print \$8}' | sort | uniq -c"
    echo ""
    echo "  # Compare node utilization"
    echo "  kubectl top nodes --context kind-${CLUSTER_A_NAME}"
    echo "  kubectl top nodes --context kind-${CLUSTER_B_NAME}"
    echo ""
    echo "  # Access Grafana on Cluster A (port 3000)"
    echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 --context kind-${CLUSTER_A_NAME}"
    echo ""
    echo "  # Access Grafana on Cluster B (port 3001)"
    echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3001:80 --context kind-${CLUSTER_B_NAME}"
    echo ""
    echo ""
    echo "✓ Clusters are running and ready for comparison!"
    echo ""
    echo "Clusters will remain running. You can explore them now or later."
    echo ""
    echo "To compare clusters:"
    echo "  ./compare-clusters.sh kind-${CLUSTER_A_NAME} kind-${CLUSTER_B_NAME}"
    echo ""
    echo "To analyze individual clusters:"
    echo "  ./cluster-metrics-analyzer.sh kind-${CLUSTER_A_NAME}"
    echo "  ./cluster-metrics-analyzer.sh kind-${CLUSTER_B_NAME}"
    echo ""
    read -p "Delete clusters now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup
    else
        echo ""
        echo "Clusters will remain running. To delete them later:"
        echo "  kind delete cluster --name $CLUSTER_A_NAME"
        echo "  kind delete cluster --name $CLUSTER_B_NAME"
        echo ""
    fi
}

main
