#!/bin/bash
# nkp-platform-bin-packing.sh
#
# Applies resource bin packing configuration to Nutanix NKP platform services
# This script helps enable bin packing for NKP management cluster platform services
#
# Usage:
#   ./nkp-platform-bin-packing.sh [action]
#   action: enable | disable | status | test
#
# Prerequisites:
#   - kubectl configured to access NKP management cluster
#   - Cluster admin permissions
#
# Example:
#   ./nkp-platform-bin-packing.sh enable
#   ./nkp-platform-bin-packing.sh status

set -e

ACTION="${1:-status}"

# Platform service namespaces
PLATFORM_NAMESPACES=(
    "kommander"
    "cert-manager"
    "gatekeeper-system"
    "kubernetes-dashboard"
    "monitoring"
)

# Scheduler configuration
SCHEDULER_CONFIG='apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
# Profile for platform services - bin packing
- name: platform-services
  pluginConfig:
  - args:
      scoringStrategy:
        resources:
        - name: cpu
          weight: 1
        - name: memory
          weight: 1
        requestedToCapacityRatio:
          shape:
          - utilization: 0
            score: 0
          - utilization: 70
            score: 7
          - utilization: 100
            score: 10
        type: RequestedToCapacityRatio
    name: NodeResourcesFit
# Default profile - spread for workloads
- name: default-scheduler
  pluginConfig:
  - args:
      scoringStrategy:
        type: LeastAllocated
    name: NodeResourcesFit'

echo "════════════════════════════════════════════════════════════════"
echo "  NKP Platform Services - Resource Bin Packing"
echo "════════════════════════════════════════════════════════════════"
echo ""

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl not found. Please install kubectl."
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo "Error: Cannot connect to Kubernetes cluster."
        echo "Please configure kubectl to access your NKP management cluster."
        exit 1
    fi
}

backup_scheduler_config() {
    echo "Backing up current scheduler configuration..."
    if kubectl get configmap kube-scheduler-config -n kube-system &>/dev/null; then
        kubectl get configmap kube-scheduler-config -n kube-system -o yaml > "scheduler-backup-$(date +%Y%m%d-%H%M%S).yaml"
        echo "✓ Backup saved"
    else
        echo "⚠ No existing scheduler config found"
    fi
}

enable_bin_packing() {
    check_kubectl
    
    echo "Action: Enable bin packing for platform services"
    echo ""
    
    # Backup current config
    backup_scheduler_config
    
    # Create scheduler config
    echo "Creating scheduler configuration..."
    echo "$SCHEDULER_CONFIG" | kubectl create configmap kube-scheduler-config \
        --from-file=config=/dev/stdin \
        -n kube-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Restart scheduler
    echo ""
    echo "Restarting kube-scheduler..."
    kubectl rollout restart deployment/kube-scheduler -n kube-system
    
    echo ""
    echo "Waiting for scheduler to be ready..."
    kubectl rollout status deployment/kube-scheduler -n kube-system --timeout=120s
    
    echo ""
    echo "✓ Bin packing enabled for platform services"
    echo ""
    echo "Note: Platform services need to specify schedulerName: platform-services"
    echo "      to use the bin packing profile."
}

disable_bin_packing() {
    check_kubectl
    
    echo "Action: Disable bin packing (restore default)"
    echo ""
    
    # Restore from backup if available
    BACKUP_FILE=$(ls -t scheduler-backup-*.yaml 2>/dev/null | head -1)
    if [ -n "$BACKUP_FILE" ]; then
        echo "Restoring from backup: $BACKUP_FILE"
        kubectl apply -f "$BACKUP_FILE"
    else
        echo "No backup found. Removing custom scheduler config..."
        kubectl delete configmap kube-scheduler-config -n kube-system 2>/dev/null || true
    fi
    
    # Restart scheduler
    echo ""
    echo "Restarting kube-scheduler..."
    kubectl rollout restart deployment/kube-scheduler -n kube-system
    
    echo ""
    echo "Waiting for scheduler to be ready..."
    kubectl rollout status deployment/kube-scheduler -n kube-system --timeout=120s
    
    echo ""
    echo "✓ Bin packing disabled (default scheduler restored)"
}

show_status() {
    check_kubectl
    
    echo "Action: Show bin packing status"
    echo ""
    
    # Check scheduler config
    echo "Scheduler Configuration:"
    if kubectl get configmap kube-scheduler-config -n kube-system &>/dev/null; then
        echo "✓ Custom scheduler config exists"
        kubectl get configmap kube-scheduler-config -n kube-system -o jsonpath='{.data.config}' | grep -q "RequestedToCapacityRatio\|MostAllocated" && \
            echo "  → Bin packing strategy detected" || \
            echo "  → No bin packing strategy found"
    else
        echo "⚠ No custom scheduler config (using defaults)"
    fi
    
    echo ""
    echo "Scheduler Status:"
    kubectl get deployment kube-scheduler -n kube-system -o wide
    
    echo ""
    echo "Platform Service Pod Distribution:"
    for ns in "${PLATFORM_NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            POD_COUNT=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            if [ "$POD_COUNT" -gt 0 ]; then
                echo ""
                echo "Namespace: $ns ($POD_COUNT pods)"
                echo "  Pods per node:"
                kubectl get pods -n "$ns" -o wide --no-headers 2>/dev/null | \
                    awk '{print $7}' | sort | uniq -c | sort -rn | \
                    awk '{printf "    %s: %d pods\n", $2, $1}' || echo "    (no pods)"
            fi
        fi
    done
    
    echo ""
    echo "Node Resource Utilization:"
    if kubectl top nodes &>/dev/null 2>&1; then
        kubectl top nodes
    else
        echo "  (metrics-server not available)"
    fi
}

test_bin_packing() {
    check_kubectl
    
    echo "Action: Test bin packing behavior"
    echo ""
    
    TEST_NAMESPACE="nkp-bin-packing-test"
    
    # Create test namespace
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "Creating test deployment with bin packing scheduler..."
    kubectl apply -n "$TEST_NAMESPACE" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bin-packing-test
spec:
  replicas: 10
  selector:
    matchLabels:
      app: bin-packing-test
  template:
    metadata:
      labels:
        app: bin-packing-test
    spec:
      schedulerName: platform-services
      containers:
      - name: test-container
        image: nginx:latest
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF
    
    echo ""
    echo "Waiting for pods to be scheduled..."
    sleep 10
    
    echo ""
    echo "Pod distribution:"
    kubectl get pods -n "$TEST_NAMESPACE" -o wide
    
    echo ""
    echo "Pods per node:"
    kubectl get pods -n "$TEST_NAMESPACE" -o wide --no-headers | \
        awk '{print $7}' | sort | uniq -c | sort -rn
    
    echo ""
    read -p "Clean up test deployment? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace "$TEST_NAMESPACE"
        echo "✓ Test deployment cleaned up"
    else
        echo "Test deployment left in namespace: $TEST_NAMESPACE"
    fi
}

case "$ACTION" in
    enable)
        enable_bin_packing
        ;;
    disable)
        disable_bin_packing
        ;;
    status)
        show_status
        ;;
    test)
        test_bin_packing
        ;;
    *)
        echo "Usage: $0 [enable|disable|status|test]"
        echo ""
        echo "Actions:"
        echo "  enable  - Enable bin packing for platform services"
        echo "  disable - Disable bin packing (restore default)"
        echo "  status  - Show current bin packing status"
        echo "  test    - Test bin packing with sample deployment"
        exit 1
        ;;
esac

echo ""
echo "Done!"
