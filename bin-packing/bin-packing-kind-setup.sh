#!/bin/bash
# bin-packing-kind-setup.sh
# 
# Sets up a kind cluster with Kubernetes resource bin packing enabled
# Demonstrates MostAllocated and RequestedToCapacityRatio strategies
#
# Approach:
#   1. Creates a standard kind cluster (no scheduler config during bootstrap)
#   2. After cluster is ready, copies scheduler config to control plane node
#   3. Modifies the static pod manifest to use the config
#   4. Kubelet automatically restarts the scheduler with bin packing enabled
#
# Usage:
#   ./bin-packing-kind-setup.sh [strategy]
#   strategy: mostallocated (default) | requestedtocapacityratio
#
# Example:
#   ./bin-packing-kind-setup.sh mostallocated
#   ./bin-packing-kind-setup.sh requestedtocapacityratio
#
# Requirements:
#   - kind installed
#   - kubectl installed
#   - Docker running
#   - Sufficient system resources (4GB+ RAM recommended)
#   - helm (optional, for kube-prometheus-stack example)

set -e

CLUSTER_NAME="${CLUSTER_NAME:-bin-packing-demo}"
STRATEGY="${1:-mostallocated}"

echo "════════════════════════════════════════════════════════════════"
echo "  Kubernetes Resource Bin Packing - Kind Cluster Setup"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Cluster Name: $CLUSTER_NAME"
echo "Strategy: $STRATEGY"
echo ""

# Cleanup function (only for temp files, NOT cluster)
cleanup() {
    # Only clean up temporary config files, NOT the cluster
    rm -f scheduler-config.yaml kind-cluster-config.yaml
}

# Register cleanup for temp files only (on script exit)
trap cleanup EXIT

# Create scheduler configuration based on strategy
echo "Creating scheduler configuration for $STRATEGY strategy..."

# Validate strategy
if [ "$STRATEGY" != "mostallocated" ] && [ "$STRATEGY" != "requestedtocapacityratio" ]; then
    echo "Error: Unknown strategy '$STRATEGY'"
    echo "Valid strategies: mostallocated, requestedtocapacityratio"
    exit 1
fi

if [ "$STRATEGY" = "mostallocated" ]; then
    cat > scheduler-config.yaml <<EOF
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- pluginConfig:
  - args:
      scoringStrategy:
        resources:
        - name: cpu
          weight: 1
        - name: memory
          weight: 1
        type: MostAllocated
    name: NodeResourcesFit
EOF
elif [ "$STRATEGY" = "requestedtocapacityratio" ]; then
    cat > scheduler-config.yaml <<EOF
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- pluginConfig:
  - args:
      scoringStrategy:
        resources:
        - name: cpu
          weight: 3
        - name: memory
          weight: 1
        requestedToCapacityRatio:
          shape:
          - utilization: 0
            score: 0
          - utilization: 50
            score: 5
          - utilization: 100
            score: 10
        type: RequestedToCapacityRatio
    name: NodeResourcesFit
EOF
fi

# Validate the YAML file was created
if [ ! -f scheduler-config.yaml ]; then
    echo "ERROR: Failed to create scheduler-config.yaml"
    exit 1
fi

echo "✓ Scheduler configuration file created"

# Create kind cluster configuration (NO scheduler config during bootstrap)
echo "Creating kind cluster configuration..."

cat > kind-cluster-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF

# Check if cluster already exists
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster $CLUSTER_NAME already exists. Deleting..."
    kind delete cluster --name "$CLUSTER_NAME"
fi

# Create cluster (without scheduler config - we'll add it after)
echo ""
echo "Creating kind cluster (this may take a few minutes)..."
if ! kind create cluster --name "$CLUSTER_NAME" --config kind-cluster-config.yaml; then
    echo "ERROR: Failed to create kind cluster"
    echo "This might be due to:"
    echo "  - Docker not running"
    echo "  - Insufficient system resources"
    echo "  - Port conflicts"
    exit 1
fi

# Wait for nodes to be ready
echo ""
echo "Waiting for nodes to be ready..."
if ! kubectl wait --for=condition=Ready nodes --all --timeout=300s --context "kind-${CLUSTER_NAME}"; then
    echo "ERROR: Nodes did not become ready in time"
    echo "Checking node status:"
    kubectl get nodes --context "kind-${CLUSTER_NAME}"
    exit 1
fi

echo "✓ Cluster is ready!"

# Apply scheduler configuration via ConfigMap
echo ""
echo "Applying scheduler configuration with $STRATEGY strategy..."
kubectl create configmap kube-scheduler-config \
    --from-file=config=scheduler-config.yaml \
    -n kube-system \
    --context "kind-${CLUSTER_NAME}" \
    --dry-run=client -o yaml | kubectl apply --context "kind-${CLUSTER_NAME}" -f -

# Update scheduler - kind uses static pods, so we need to modify the manifest on the node
echo ""
echo "Updating kube-scheduler to use bin packing configuration..."

# Copy config file to the control plane node
CONTROL_PLANE="${CLUSTER_NAME}-control-plane"

# Verify control plane container exists
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTROL_PLANE}$"; then
    echo "ERROR: Control plane container ${CONTROL_PLANE} not found"
    exit 1
fi

echo "Copying scheduler config to control plane node..."
docker cp scheduler-config.yaml "${CONTROL_PLANE}:/etc/kubernetes/scheduler-config.yaml"

# Verify file was copied
if ! docker exec "${CONTROL_PLANE}" test -f /etc/kubernetes/scheduler-config.yaml; then
    echo "ERROR: Failed to copy scheduler config file"
    exit 1
fi
echo "✓ Scheduler config file copied"

# Validate the config file is valid YAML
echo "Validating scheduler config..."
if ! docker exec "${CONTROL_PLANE}" sh -c 'command -v yq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1'; then
    echo "Note: Cannot validate YAML (yq/python3 not available), proceeding anyway..."
else
    # Try to validate with python if available
    docker exec "${CONTROL_PLANE}" python3 -c "import yaml; yaml.safe_load(open('/etc/kubernetes/scheduler-config.yaml'))" 2>/dev/null && echo "✓ Config file is valid YAML" || echo "Warning: Could not validate YAML syntax"
fi

# Modify the static pod manifest on the node
echo "Modifying scheduler static pod manifest..."
docker exec "${CONTROL_PLANE}" sh -c '
  # Backup original manifest
  cp /etc/kubernetes/manifests/kube-scheduler.yaml /etc/kubernetes/manifests/kube-scheduler.yaml.bak 2>/dev/null || true
  
  # Check if --config already exists
  if grep -q "config=/etc/kubernetes/scheduler-config.yaml" /etc/kubernetes/manifests/kube-scheduler.yaml; then
    echo "Config argument already exists"
  else
    # Add --config argument after kube-scheduler command
    # Use a more robust sed command
    sed -i "/^\s*- kube-scheduler$/a\    - --config=/etc/kubernetes/scheduler-config.yaml" /etc/kubernetes/manifests/kube-scheduler.yaml
    echo "Added --config argument to scheduler manifest"
  fi
  
  # Verify the change
  echo "Current scheduler command:"
  grep -A 10 "command:" /etc/kubernetes/manifests/kube-scheduler.yaml | head -15
'

echo "Scheduler configuration updated. Waiting for scheduler to restart..."

# Note: Static pods restart automatically when manifest changes, no need for rollout restart

# Wait for scheduler pod to be ready (static pod, so check pod directly)
echo ""
echo "Waiting for scheduler to restart with new config..."
sleep 15  # Give kubelet time to detect manifest change and restart

for i in {1..40}; do
    SCHEDULER_STATUS=$(kubectl get pods -n kube-system --context "kind-${CLUSTER_NAME}" -l component=kube-scheduler --field-selector=status.phase=Running -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$SCHEDULER_STATUS" = "Running" ]; then
        echo "✓ Scheduler is running"
        break
    fi
    if [ $i -eq 40 ]; then
        echo "WARNING: Scheduler may not have restarted properly"
        echo "Checking scheduler status:"
        kubectl get pods -n kube-system --context "kind-${CLUSTER_NAME}" -l component=kube-scheduler
        echo ""
        echo "Checking scheduler logs:"
        kubectl logs -n kube-system --context "kind-${CLUSTER_NAME}" -l component=kube-scheduler --tail=20 || true
    else
        echo "Waiting for scheduler... ($i/40) - Status: $SCHEDULER_STATUS"
        sleep 3
    fi
done

# Verify scheduler configuration
echo ""
echo "Verifying scheduler configuration..."
sleep 5
kubectl logs -n kube-system -l component=kube-scheduler --context "kind-${CLUSTER_NAME}" --tail=30 | grep -i "bin\|pack\|most\|allocated" || echo "Scheduler logs (checking for errors)..."
kubectl logs -n kube-system -l component=kube-scheduler --context "kind-${CLUSTER_NAME}" --tail=10 || true

# Install metrics-server (required for kubectl top)
echo ""
echo "Installing metrics-server..."
kubectl apply --context "kind-${CLUSTER_NAME}" -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server for kind (disable TLS verification)
kubectl patch deployment metrics-server -n kube-system \
    --context "kind-${CLUSTER_NAME}" \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Wait for metrics-server to be ready
echo "Waiting for metrics-server to be ready..."
kubectl wait --for=condition=available deployment/metrics-server -n kube-system \
    --context "kind-${CLUSTER_NAME}" \
    --timeout=120s || echo "Metrics-server may take longer to start..."

echo "✓ Metrics-server installed"

# Create test deployment
echo ""
echo "Creating test deployment to demonstrate bin packing..."
kubectl apply --context "kind-${CLUSTER_NAME}" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bin-packing-test
spec:
  replicas: 15
  selector:
    matchLabels:
      app: bin-packing-test
  template:
    metadata:
      labels:
        app: bin-packing-test
    spec:
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
sleep 15

# Show results
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Results: Pod Distribution Across Nodes"
echo "════════════════════════════════════════════════════════════════"
echo ""
kubectl get pods --context "kind-${CLUSTER_NAME}" -o wide | grep bin-packing-test || true

echo ""
echo "Pod count per node:"
kubectl get pods --context "kind-${CLUSTER_NAME}" -o wide | grep bin-packing-test | awk '{print $7}' | sort | uniq -c | sort -rn || true

echo ""
echo "Node resource allocation:"
sleep 5  # Give metrics-server time to collect metrics
kubectl top nodes --context "kind-${CLUSTER_NAME}" 2>/dev/null || echo "Metrics server is starting up, metrics may not be available yet..."

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Cluster Setup Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Cluster context: kind-${CLUSTER_NAME}"
echo ""
echo "To interact with the cluster:"
echo "  kubectl --context kind-${CLUSTER_NAME} get nodes"
echo "  kubectl --context kind-${CLUSTER_NAME} get pods -o wide"
# Optional: Install kube-prometheus-stack as example platform service
echo ""
read -p "Install kube-prometheus-stack as example platform service? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Installing kube-prometheus-stack with bin packing enabled..."
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        echo "Helm is not installed. Installing helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || {
            echo "Failed to install helm. Please install helm manually:"
            echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
            echo "Skipping kube-prometheus-stack installation..."
        }
    fi
    
    if command -v helm &> /dev/null; then
        # Add prometheus-community repo
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        helm repo update
        
        # Create values file for bin packing
        cat > /tmp/prometheus-bin-packing-values.yaml <<EOF
# kube-prometheus-stack with bin packing scheduler
# This demonstrates how to configure platform services to use bin packing

# Global scheduler configuration
global:
  schedulerName: ""  # Will be set per component

# Prometheus configuration
prometheus:
  prometheusSpec:
    # Use bin packing scheduler for Prometheus pods
    schedulerName: ""
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi
    # Reduce replicas for demo
    replicas: 1
    retention: 7d
    retentionSize: 10GB

# Alertmanager configuration
alertmanager:
  alertmanagerSpec:
    # Use bin packing scheduler
    schedulerName: ""
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
    replicas: 1

# Grafana configuration
grafana:
  # Use bin packing scheduler
  schedulerName: ""
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  persistence:
    enabled: false  # Disable for kind demo

# Node exporter (DaemonSet - runs on all nodes)
nodeExporter:
  resources:
    requests:
      cpu: 100m
      memory: 64Mi

# Kube state metrics
kubeStateMetrics:
  # Use bin packing scheduler
  schedulerName: ""
  resources:
    requests:
      cpu: 100m
      memory: 256Mi

# Disable some components for smaller demo
prometheusOperator:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
EOF
        
        # Install with bin packing enabled
        # Note: For kind clusters, we modified the default scheduler, so we don't need to set schedulerName
        # The default scheduler will use bin packing automatically
        echo "Installing kube-prometheus-stack..."
        echo "Note: Using default scheduler (which has bin packing enabled)"
        
        helm install prometheus prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --create-namespace \
            --values /tmp/prometheus-bin-packing-values.yaml \
            --wait \
            --timeout 10m \
            --kube-context "kind-${CLUSTER_NAME}" || {
            echo "Helm installation failed or timed out. This is okay for demo purposes."
            echo "You can install it manually later with:"
            echo "  helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace"
            echo "  See examples/prometheus-bin-packing-example.yaml for configuration"
        }
        
        if [ $? -eq 0 ]; then
            echo "✓ kube-prometheus-stack installed"
            echo ""
            echo "Waiting for Prometheus pods to be scheduled..."
            sleep 10
            
            echo ""
            echo "Prometheus stack pod distribution:"
            kubectl get pods -n monitoring --context "kind-${CLUSTER_NAME}" -o wide
            
            echo ""
            echo "Pods per node:"
            kubectl get pods -n monitoring --context "kind-${CLUSTER_NAME}" -o wide --no-headers 2>/dev/null | \
                awk '{print $7}' | sort | uniq -c | sort -rn || echo "No pods scheduled yet"
            
            echo ""
            echo "Note: Bin packing is enabled via the default scheduler configuration."
            echo "      All pods will automatically use bin packing (no schedulerName needed)."
            echo ""
            echo "Access Grafana (port-forward):"
            echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 --context kind-${CLUSTER_NAME}"
            echo "  Default credentials: admin / prom-operator"
        fi
        
        rm -f /tmp/prometheus-bin-packing-values.yaml
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Cluster is ready for testing!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "The cluster will remain running. To delete it later, run:"
echo "  kind delete cluster --name $CLUSTER_NAME"
echo ""
echo "To verify bin packing is working:"
echo "  1. Check scheduler logs: kubectl logs -n kube-system --context kind-${CLUSTER_NAME} -l component=kube-scheduler"
echo "  2. Deploy more pods and observe they concentrate on fewer nodes"
echo "  3. Check pod distribution: kubectl get pods -A --context kind-${CLUSTER_NAME} -o wide | awk '{print \$8}' | sort | uniq -c"
echo "  4. View node metrics: kubectl top nodes --context kind-${CLUSTER_NAME}"
echo ""
echo "Example: Install kube-prometheus-stack manually with bin packing:"
echo "  See examples/prometheus-bin-packing-example.yaml"
echo ""
