# Kubernetes Resource Bin Packing Guide

> **Reference:** [Kubernetes Resource Bin Packing Documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/resource-bin-packing/)
>
> **Last Updated:** January 2026

---

## Table of Contents

1. [What is Resource Bin Packing?](#what-is-resource-bin-packing)
2. [Why Use Bin Packing?](#why-use-bin-packing)
3. [How Bin Packing Works](#how-bin-packing-works)
4. [Enabling Bin Packing Strategies](#enabling-bin-packing-strategies)
5. [Kind Cluster Example](#kind-cluster-example)
6. [Bin Packing for Nutanix NKP Platform Services](#bin-packing-for-nutanix-nkp-platform-services)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## What is Resource Bin Packing?

**Resource bin packing** is a Kubernetes scheduler strategy that optimizes cluster resource utilization by **favoring nodes with higher resource allocation**. Instead of spreading pods evenly across nodes (which can leave many nodes partially utilized), bin packing concentrates workloads on fewer nodes, maximizing resource density.

### Key Concepts

| Term | Description |
|------|-------------|
| **Bin Packing** | Algorithm that packs items (pods) into bins (nodes) to minimize the number of bins used |
| **MostAllocated** | Scoring strategy that favors nodes with highest resource utilization |
| **RequestedToCapacityRatio** | Customizable scoring strategy based on request-to-capacity ratios |
| **NodeResourcesFit Plugin** | Kubernetes scheduler plugin that performs resource-based filtering and scoring |

### Default Behavior vs Bin Packing

**Default Kubernetes Scheduler Behavior:**
- Uses `LeastAllocated` strategy (default)
- Spreads pods across nodes to balance load
- Minimizes resource contention
- **Result:** Many nodes partially utilized

**Bin Packing Behavior:**
- Uses `MostAllocated` or `RequestedToCapacityRatio` strategy
- Concentrates pods on fewer nodes
- Maximizes resource utilization
- **Result:** Fewer nodes with higher utilization, more nodes available for other workloads

---

## Why Use Bin Packing?

### Benefits

1. **Higher Resource Utilization**
   - Reduces wasted capacity
   - Better ROI on infrastructure
   - Fewer nodes needed for same workload

2. **Cost Optimization**
   - Lower infrastructure costs
   - Better cloud resource efficiency
   - Reduced operational overhead

3. **Workload Density**
   - More pods per node
   - Better for batch workloads
   - Ideal for resource-constrained environments

### When to Use Bin Packing

✅ **Good for:**
- Batch processing workloads
- Development/test environments
- Cost-sensitive deployments
- Workloads with predictable resource usage
- When you want to maximize node utilization

❌ **Not ideal for:**
- High-availability production workloads (spread for resilience)
- Workloads with unpredictable resource spikes
- When you need to minimize resource contention
- Multi-tenant environments requiring isolation

---

## How Bin Packing Works

### Scheduler Scoring Process

The Kubernetes scheduler uses a **two-phase approach**:

1. **Filtering Phase**: Eliminates nodes that cannot run the pod
2. **Scoring Phase**: Ranks remaining nodes (0-100 score)

Bin packing affects the **scoring phase** through the `NodeResourcesFit` plugin.

### Scoring Strategies

#### 1. MostAllocated Strategy

Favors nodes with the **highest resource utilization**:

```
Score = (Allocated Resources / Total Capacity) × Weight
```

**Example:**
- Node A: 8 CPU allocated / 16 CPU total = 50% utilization
- Node B: 12 CPU allocated / 16 CPU total = 75% utilization
- **Node B gets higher score** (more allocated)

#### 2. RequestedToCapacityRatio Strategy

Customizable scoring based on a **function of request-to-capacity ratio**:

```
Score = f((Requested + Used) / Capacity)
```

Where `f()` is a configurable shape function that maps utilization to score.

**Shape Function Example:**
```yaml
shape:
  - utilization: 0    # 0% utilization
    score: 0         # Score = 0
  - utilization: 100 # 100% utilization
    score: 10        # Score = 10
```

This creates a **linear function** favoring higher utilization.

---

## Enabling Bin Packing Strategies

### Strategy 1: MostAllocated

**Configuration:**

```yaml
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
```

**Key Parameters:**
- `type: MostAllocated` - Enables bin packing
- `resources` - List of resources to consider
- `weight` - Relative importance of each resource (default: 1)

### Strategy 2: RequestedToCapacityRatio

**Configuration:**

```yaml
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
          - utilization: 100
            score: 10
        type: RequestedToCapacityRatio
    name: NodeResourcesFit
```

**Key Parameters:**
- `type: RequestedToCapacityRatio` - Enables custom bin packing
- `shape` - Function mapping utilization to score
- `resources` - Resources to consider with weights

### Tuning the Shape Function

**Bin Packing (Most Requested):**
```yaml
shape:
  - utilization: 0
    score: 0      # Low utilization = low score
  - utilization: 100
    score: 10     # High utilization = high score
```

**Spread Packing (Least Requested):**
```yaml
shape:
  - utilization: 0
    score: 10     # Low utilization = high score
  - utilization: 100
    score: 0      # High utilization = low score
```

**Custom Curve (Balanced):**
```yaml
shape:
  - utilization: 0
    score: 0
  - utilization: 50
    score: 5      # Medium utilization = medium score
  - utilization: 100
    score: 10
```

---

## Kind Cluster Example

This section provides a complete example of enabling bin packing on a **kind** (Kubernetes in Docker) cluster.

### Prerequisites

```bash
# Install kind
brew install kind  # macOS
# or
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Install kubectl
brew install kubectl  # macOS
# or follow: https://kubernetes.io/docs/tasks/tools/
```

### Step 1: Create Kind Cluster with Custom Scheduler Config

Create a scheduler configuration file:

```yaml
# scheduler-config.yaml
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
```

Create a kind cluster configuration that mounts this config:

```yaml
# kind-cluster-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: ./scheduler-config.yaml
    containerPath: /etc/kubernetes/scheduler-config.yaml
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    scheduler:
      extraArgs:
        config: /etc/kubernetes/scheduler-config.yaml
```

**Create the cluster:**

```bash
# Create the cluster
kind create cluster --name bin-packing-demo --config kind-cluster-config.yaml

# Verify cluster is running
kubectl cluster-info --context kind-bin-packing-demo
```

### Step 2: Verify Scheduler Configuration

```bash
# Check scheduler pod logs
kubectl logs -n kube-system -l component=kube-scheduler --tail=50

# Verify scheduler is using custom config
kubectl get configmap -n kube-system kube-scheduler -o yaml
```

### Step 3: Test Bin Packing Behavior

**Create test deployment:**

```yaml
# test-deployment.yaml
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
```

**Deploy and observe:**

```bash
# Apply deployment
kubectl apply -f test-deployment.yaml

# Watch pods being scheduled
kubectl get pods -o wide -w

# Check node resource allocation
kubectl top nodes

# Check pod distribution
kubectl get pods -o wide | grep bin-packing-test
```

**Expected Behavior:**
- Pods should concentrate on fewer nodes
- Nodes with higher utilization get more pods
- Fewer nodes used overall

### Step 4: Compare with Default Behavior

**Reset to default (LeastAllocated):**

```yaml
# scheduler-config-default.yaml
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
        type: LeastAllocated  # Default behavior
    name: NodeResourcesFit
```

**Restart scheduler with default config:**

```bash
# Update configmap
kubectl create configmap kube-scheduler-config \
  --from-file=config=scheduler-config-default.yaml \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Restart scheduler
kubectl delete pod -n kube-system -l component=kube-scheduler

# Redeploy and observe different distribution
kubectl delete deployment bin-packing-test
kubectl apply -f test-deployment.yaml
kubectl get pods -o wide
```

**Comparison:**
- **Default (LeastAllocated)**: Pods spread evenly across nodes
- **Bin Packing (MostAllocated)**: Pods concentrate on fewer nodes

### Step 5: Advanced Example with RequestedToCapacityRatio

**Custom bin packing with extended resources:**

```yaml
# scheduler-config-advanced.yaml
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
        - name: nvidia.com/gpu
          weight: 5
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
```

**Apply and test:**

```bash
# Update scheduler config
kubectl create configmap kube-scheduler-config \
  --from-file=config=scheduler-config-advanced.yaml \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Restart scheduler
kubectl delete pod -n kube-system -l component=kube-scheduler
```

### Complete Example Script

```bash
#!/bin/bash
# setup-bin-packing-kind.sh

set -e

echo "Creating kind cluster with bin packing scheduler configuration..."

# Create scheduler config
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

# Create kind config
cat > kind-cluster-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: ./scheduler-config.yaml
    containerPath: /etc/kubernetes/scheduler-config.yaml
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    scheduler:
      extraArgs:
        config: /etc/kubernetes/scheduler-config.yaml
- role: worker
- role: worker
- role: worker
EOF

# Create cluster
kind create cluster --name bin-packing-demo --config kind-cluster-config.yaml

# Wait for nodes to be ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "Cluster created! Verifying scheduler configuration..."
kubectl logs -n kube-system -l component=kube-scheduler --tail=20

echo "Creating test deployment..."
kubectl apply -f - <<EOF
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

echo "Waiting for pods to be scheduled..."
sleep 10

echo "Pod distribution across nodes:"
kubectl get pods -o wide | grep bin-packing-test

echo "Node resource utilization:"
kubectl top nodes

echo "Done! Observe that pods are concentrated on fewer nodes."
```

**Run the script:**

```bash
chmod +x setup-bin-packing-kind.sh
./setup-bin-packing-kind.sh
```

---

## Bin Packing for Nutanix NKP Platform Services

This section documents the strategy for applying bin packing to **Nutanix NKP (Nutanix Kubernetes Platform) platform services and pods** to increase density and reduce infrastructure costs.

### Understanding NKP Platform Services

NKP platform services include:
- **Kommander** (multi-cluster management)
- **Prometheus** (metrics)
- **Grafana** (visualization)
- **Loki** (logging)
- **Gatekeeper** (policy)
- **Traefik** (ingress)
- **Cert-Manager** (certificates)
- **Kubecost** (cost monitoring)
- And more...

**Reference:** See [NKP Platform Applications Guide](../nkp/NKP-Platform-Applications-Guide.md) for complete list.

### Strategy Overview

#### Phase 1: Assessment

**1. Identify Platform Service Namespaces**

```bash
# List all platform namespaces
kubectl get namespaces -l app.kubernetes.io/part-of=kommander

# Common NKP platform namespaces:
# - kommander
# - cert-manager
# - gatekeeper-system
# - kubernetes-dashboard
# - monitoring (if using Prometheus Operator)
```

**2. Analyze Current Resource Distribution**

```bash
# Get resource requests/limits for platform pods
kubectl get pods -n kommander -o json | \
  jq '.items[] | {name: .metadata.name, node: .spec.nodeName, requests: .spec.containers[].resources.requests}'

# Check node utilization
kubectl top nodes

# Count pods per node
kubectl get pods -A -o wide | awk '{print $7}' | sort | uniq -c | sort -rn
```

**3. Identify Bin Packing Candidates**

**Good candidates for bin packing:**
- ✅ Stateless services (Prometheus, Grafana, Traefik)
- ✅ Services with predictable resource usage
- ✅ Services that can tolerate co-location
- ✅ Development/test environments

**Avoid bin packing for:**
- ❌ High-availability critical services (unless using anti-affinity)
- ❌ Services with unpredictable spikes
- ❌ Services requiring strict isolation

#### Phase 2: Scheduler Configuration

**Option A: Cluster-Wide Bin Packing**

Apply bin packing to the entire cluster (affects all pods):

```yaml
# nkp-scheduler-config.yaml
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
```

**Apply to NKP management cluster:**

```bash
# Create configmap
kubectl create configmap kube-scheduler-config \
  --from-file=config=nkp-scheduler-config.yaml \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Restart scheduler
kubectl delete pod -n kube-system -l component=kube-scheduler
```

**Option B: Selective Bin Packing with Scheduler Profiles**

Use multiple scheduler profiles - one for platform services, one for workloads:

```yaml
# nkp-scheduler-multi-profile.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
# Default profile - spread workloads
- name: default-scheduler
  pluginConfig:
  - args:
      scoringStrategy:
        type: LeastAllocated
    name: NodeResourcesFit

# Bin packing profile for platform services
- name: platform-bin-packing
  pluginConfig:
  - args:
      scoringStrategy:
        resources:
        - name: cpu
          weight: 1
        - name: memory
          weight: 1
        type: MostAllocated
    name: NodeResourcesFit
```

**Use the profile in platform service deployments:**

```yaml
# Example: Prometheus with bin packing scheduler
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: kommander
spec:
  template:
    spec:
      schedulerName: platform-bin-packing  # Use bin packing scheduler
      containers:
      - name: prometheus
        # ... container spec
```

#### Phase 3: Node Affinity and Taints

**Dedicate nodes for platform services (optional):**

```yaml
# Label nodes for platform services
kubectl label nodes <node-name> platform-services=true

# Taint nodes (optional - requires toleration)
kubectl taint nodes <node-name> platform-services=true:NoSchedule
```

**Add node affinity to platform services:**

```yaml
# Example: Prometheus with node affinity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: kommander
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: platform-services
                operator: In
                values:
                - "true"
      containers:
      - name: prometheus
        # ... container spec
```

#### Phase 4: Resource Optimization

**1. Right-Size Resource Requests**

Review and optimize resource requests for platform services:

```bash
# Check actual resource usage
kubectl top pods -n kommander

# Compare with requests
kubectl get pods -n kommander -o json | \
  jq '.items[] | {name: .metadata.name, requests: .spec.containers[].resources.requests, limits: .spec.containers[].resources.limits}'
```

**2. Adjust Resource Requests Based on Usage**

```yaml
# Example: Optimized Prometheus resources
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: kommander
spec:
  template:
    spec:
      containers:
      - name: prometheus
        resources:
          requests:
            cpu: 1000m      # Based on actual usage
            memory: 4Gi     # Based on actual usage
          limits:
            cpu: 2000m
            memory: 8Gi
```

**3. Use Vertical Pod Autoscaler (VPA)**

Automatically adjust resource requests based on usage:

```yaml
# Example VPA for Prometheus
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: prometheus-vpa
  namespace: kommander
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: prometheus
  updatePolicy:
    updateMode: "Auto"  # or "Off" for recommendations only
```

#### Phase 5: Pod Disruption Budgets and Anti-Affinity

**Ensure high availability despite bin packing:**

```yaml
# Example: Prometheus PDB
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: prometheus-pdb
  namespace: kommander
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: prometheus
```

**Use pod anti-affinity to spread critical services:**

```yaml
# Example: Prometheus with anti-affinity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: kommander
spec:
  replicas: 2
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - prometheus
              topologyKey: kubernetes.io/hostname
```

### Implementation Plan for NKP

#### Step-by-Step Rollout

**1. Test Environment First**

```bash
# Create test namespace
kubectl create namespace nkp-bin-packing-test

# Deploy test platform services with bin packing
# Monitor behavior for 1-2 weeks
```

**2. Gradual Rollout**

- Week 1: Enable for non-critical services (Kubernetes Dashboard, Grafana)
- Week 2: Enable for observability stack (Prometheus, Loki)
- Week 3: Enable for management services (Kommander components)
- Week 4: Enable for security services (Gatekeeper, Cert-Manager)

**3. Monitor and Adjust**

```bash
# Monitor node utilization
watch kubectl top nodes

# Monitor pod distribution
kubectl get pods -A -o wide | grep -E "kommander|cert-manager|gatekeeper"

# Check for resource contention
kubectl describe nodes | grep -A 10 "Allocated resources"
```

### NKP-Specific Configuration Example

**Complete scheduler configuration for NKP platform services:**

```yaml
# nkp-platform-bin-packing.yaml
apiVersion: kubescheduler.config.k8s.io/v1
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
            score: 7      # Favor 70% utilization
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
    name: NodeResourcesFit
```

**Apply to NKP cluster:**

```bash
# Backup current config
kubectl get configmap kube-scheduler-config -n kube-system -o yaml > scheduler-backup.yaml

# Apply new config
kubectl create configmap kube-scheduler-config \
  --from-file=config=nkp-platform-bin-packing.yaml \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Restart scheduler
kubectl rollout restart deployment/kube-scheduler -n kube-system
```

### Expected Results

**Before Bin Packing:**
- Platform services spread across 10 nodes
- Average node utilization: 30-40%
- Total nodes needed: 10

**After Bin Packing:**
- Platform services concentrated on 5-6 nodes
- Average node utilization: 60-70%
- Total nodes needed: 5-6 (40-50% reduction)

**Cost Savings:**
- 40-50% reduction in infrastructure for platform services
- Better resource utilization
- More nodes available for workloads

---

## Best Practices

### 1. Gradual Rollout

- ✅ Start with non-critical services
- ✅ Monitor for 1-2 weeks before expanding
- ✅ Use canary deployments when possible

### 2. Monitor Key Metrics

```bash
# Node utilization
kubectl top nodes

# Pod distribution
kubectl get pods -A -o wide | awk '{print $7}' | sort | uniq -c

# Resource contention
kubectl describe nodes | grep -A 10 "Allocated resources"

# OOMKilled events
kubectl get events --sort-by='.lastTimestamp' | grep OOMKilled
```

### 3. Set Appropriate Resource Requests

- ✅ Set requests based on actual usage (use VPA recommendations)
- ✅ Leave headroom for spikes (requests < limits)
- ✅ Monitor and adjust regularly

### 4. Use Pod Disruption Budgets

- ✅ Ensure minimum availability during node maintenance
- ✅ Balance bin packing with high availability

### 5. Consider Workload Characteristics

- ✅ Bin pack stateless, predictable workloads
- ✅ Spread stateful, critical workloads
- ✅ Use anti-affinity for HA requirements

### 6. Regular Review

- ✅ Review node utilization monthly
- ✅ Adjust resource requests quarterly
- ✅ Re-evaluate bin packing strategy as cluster grows

---

## Troubleshooting

### Issue: Pods Not Concentrating on Nodes

**Symptoms:**
- Pods still spread evenly across nodes
- No change in distribution after enabling bin packing

**Solutions:**

```bash
# Verify scheduler configuration
kubectl get configmap kube-scheduler-config -n kube-system -o yaml

# Check scheduler logs
kubectl logs -n kube-system -l component=kube-scheduler --tail=100

# Verify scheduler is using custom config
kubectl describe pod -n kube-system -l component=kube-scheduler | grep -i config
```

### Issue: Resource Contention

**Symptoms:**
- High CPU throttling
- OOMKilled pods
- Slow pod startup

**Solutions:**

```bash
# Check node resource allocation
kubectl describe nodes | grep -A 10 "Allocated resources"

# Review resource requests vs limits
kubectl get pods -A -o json | jq '.items[] | {name: .metadata.name, requests: .spec.containers[].resources.requests, limits: .spec.containers[].resources.limits}'

# Adjust resource requests
# Consider reducing bin packing aggressiveness (lower weight on CPU)
```

### Issue: High Availability Concerns

**Symptoms:**
- Too many pods on single node
- Risk of single point of failure

**Solutions:**

```yaml
# Add pod anti-affinity
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: my-app
        topologyKey: kubernetes.io/hostname

# Use pod disruption budgets
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-app
```

### Issue: Scheduler Configuration Not Applied

**Symptoms:**
- Scheduler still using default behavior
- ConfigMap exists but not used

**Solutions:**

```bash
# Verify scheduler command line args
kubectl describe pod -n kube-system -l component=kube-scheduler | grep -i "config"

# Check if config file path is correct
kubectl exec -n kube-system -l component=kube-scheduler -- ls -la /etc/kubernetes/

# Restart scheduler
kubectl delete pod -n kube-system -l component=kube-scheduler
```

---

## References

- [Kubernetes Resource Bin Packing Documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/resource-bin-packing/)
- [Kubernetes Scheduler Configuration](https://kubernetes.io/docs/reference/scheduling/config/)
- [NodeResourcesFit Plugin](https://kubernetes.io/docs/reference/scheduling/config/#scheduling-plugins)
- [NKP Platform Applications Guide](../nkp/NKP-Platform-Applications-Guide.md)
- [NKP Sizing & Scale Guide](../nkp/NKP-Sizing-Scale-Guide.md)

---

*Document generated: January 2026*
*For the latest Kubernetes scheduler features, refer to the official Kubernetes documentation.*
