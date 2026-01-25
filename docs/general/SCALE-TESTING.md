# Cluster API Scale Testing Guide

This guide covers techniques for simulating 1000+ Cluster API (CAPI) clusters with minimal resources, useful when CAPD (Cluster API Provider Docker) isn't available or when you need lightweight testing.

## Overview

| Method | Resources per "Cluster" | Best For |
|--------|------------------------|----------|
| **KWOK** | ~36KB/node | Testing node scaling, scheduling |
| **Paused CAPI Objects** | ~1KB/object | Testing GitOps, Flux reconciliation |
| **vcluster** | ~128MB/cluster | Testing actual workloads in isolation |
| **Kubemark** | ~50MB/node | API server load testing |

---

## Option 1: KWOK (Kubernetes Without Kubelet) - Recommended

KWOK is the most resource-efficient option - it can simulate 1000s of nodes using only ~36MB memory per 1000 nodes!

### Installation

```bash
# macOS
brew install kwok

# Or via go install
go install sigs.k8s.io/kwok/cmd/kwok@latest
go install sigs.k8s.io/kwok/cmd/kwokctl@latest

# Linux
KWOK_REPO=kubernetes-sigs/kwok
KWOK_LATEST_RELEASE=$(curl "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')
wget -O kwokctl "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwokctl-$(go env GOOS)-$(go env GOARCH)"
chmod +x kwokctl
sudo mv kwokctl /usr/local/bin/
```

### Create Simulated Clusters

```bash
# Create a single simulated cluster (very lightweight)
kwokctl create cluster --name test-cluster-1

# Verify
kubectl --context kwok-test-cluster-1 get nodes

# Scale to simulate many nodes within the cluster
kubectl --context kwok-test-cluster-1 scale node fake-node --replicas=100
```

### Create Multiple KWOK Clusters

```bash
#!/bin/bash
# create-kwok-clusters.sh

COUNT=${1:-100}

echo "Creating $COUNT KWOK clusters..."

for i in $(seq 1 $COUNT); do
  echo "Creating cluster-$i..."
  kwokctl create cluster --name "cluster-$i" --wait 5m &

  # Batch to avoid overwhelming the system
  if (( i % 10 == 0 )); then
    wait
    echo "Created $i clusters so far..."
  fi
done

wait
echo "✓ Created $COUNT KWOK clusters"

# List all clusters
kwokctl get clusters
```

### Cleanup KWOK Clusters

```bash
#!/bin/bash
# cleanup-kwok-clusters.sh

for cluster in $(kwokctl get clusters -o name); do
  echo "Deleting $cluster..."
  kwokctl delete cluster --name "$cluster" &
done
wait
echo "✓ All KWOK clusters deleted"
```

---

## Option 2: Paused CAPI Cluster Objects

Create fake/mock Cluster objects without actual infrastructure provisioning. This is ideal for testing GitOps reconciliation, Flux, and ArgoCD.

### Single Paused Cluster

```yaml
# fake-cluster.yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: sim-cluster-0001
  namespace: dm-dev-workspace
  annotations:
    cluster.x-k8s.io/paused: "true"
    simulation: "true"
  labels:
    simulation: "true"
    batch: "scale-test"
spec:
  paused: true
  clusterNetwork:
    pods:
      cidrBlocks:
        - 192.168.0.0/16
    services:
      cidrBlocks:
        - 10.96.0.0/12
    serviceDomain: cluster.local
```

### Generate 1000 Paused Clusters

```bash
#!/bin/bash
# generate-paused-clusters.sh
#
# Creates paused CAPI Cluster objects for scale testing
# These objects don't provision actual infrastructure

set -euo pipefail

NAMESPACE="${NAMESPACE:-dm-dev-workspace}"
COUNT="${COUNT:-1000}"
BATCH_SIZE="${BATCH_SIZE:-50}"

echo "Creating $COUNT simulated cluster objects in namespace $NAMESPACE"
echo "Batch size: $BATCH_SIZE"

# Ensure namespace exists
kubectl get namespace "$NAMESPACE" &>/dev/null || kubectl create namespace "$NAMESPACE"

start_time=$(date +%s)

for i in $(seq 1 $COUNT); do
  cat <<EOF | kubectl apply -f - 2>/dev/null &
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: sim-cluster-$(printf "%04d" $i)
  namespace: $NAMESPACE
  annotations:
    cluster.x-k8s.io/paused: "true"
    simulation: "true"
    created-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  labels:
    simulation: "true"
    batch: "scale-test"
    index: "$(printf "%04d" $i)"
spec:
  paused: true
  clusterNetwork:
    pods:
      cidrBlocks:
        - "10.$((i/256)).$((i%256)).0/24"
    services:
      cidrBlocks:
        - "10.96.0.0/12"
    serviceDomain: cluster.local
EOF

  # Batch commits to avoid overwhelming API server
  if (( i % BATCH_SIZE == 0 )); then
    wait
    elapsed=$(($(date +%s) - start_time))
    rate=$(echo "scale=2; $i / $elapsed" | bc 2>/dev/null || echo "N/A")
    echo "Created $i/$COUNT clusters... (${rate} clusters/sec)"
  fi
done

wait

end_time=$(date +%s)
total_time=$((end_time - start_time))

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✓ Created $COUNT simulated clusters in ${total_time} seconds"
echo "════════════════════════════════════════════════════════════════"

# Verify
echo ""
echo "Verification:"
kubectl get clusters -n "$NAMESPACE" -l simulation=true --no-headers | wc -l | xargs echo "  Total clusters:"
```

### Cleanup Paused Clusters

```bash
#!/bin/bash
# cleanup-paused-clusters.sh

NAMESPACE="${NAMESPACE:-dm-dev-workspace}"

echo "Deleting all simulated clusters in namespace $NAMESPACE..."

kubectl delete clusters -n "$NAMESPACE" -l simulation=true --wait=false

echo "✓ Deletion initiated (running in background)"
echo ""
echo "Monitor with:"
echo "  watch kubectl get clusters -n $NAMESPACE -l simulation=true --no-headers | wc -l"
```

---

## Option 3: vcluster (Virtual Clusters)

vcluster creates lightweight virtual clusters inside a host cluster - much less resource-intensive than real clusters, but still functional.

### Installation

```bash
# macOS
brew install loft-sh/tap/vcluster

# Linux/Other
curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64"
chmod +x vcluster
sudo mv vcluster /usr/local/bin/
```

### Create Virtual Clusters

```bash
#!/bin/bash
# create-vclusters.sh
#
# Creates lightweight virtual clusters
# Each vcluster uses ~128MB memory by default

COUNT=${1:-50}
NAMESPACE_PREFIX="vcluster"

echo "Creating $COUNT virtual clusters..."

for i in $(seq 1 $COUNT); do
  ns="${NAMESPACE_PREFIX}-$(printf "%03d" $i)"

  # Create namespace
  kubectl create namespace "$ns" 2>/dev/null || true

  # Create vcluster (don't connect, just create)
  vcluster create "vc-$(printf "%03d" $i)" \
    --namespace "$ns" \
    --connect=false \
    --update-current=false &

  # Batch to avoid overwhelming
  if (( i % 5 == 0 )); then
    wait
    echo "Created $i virtual clusters..."
  fi
done

wait
echo "✓ Created $COUNT virtual clusters"

# List all vclusters
vcluster list
```

### Cleanup Virtual Clusters

```bash
#!/bin/bash
# cleanup-vclusters.sh

for vc in $(vcluster list --output json | jq -r '.[].Name'); do
  ns=$(vcluster list --output json | jq -r ".[] | select(.Name==\"$vc\") | .Namespace")
  echo "Deleting $vc in namespace $ns..."
  vcluster delete "$vc" -n "$ns" &
done

wait
echo "✓ All virtual clusters deleted"
```

---

## Option 4: Kubemark (Hollow Nodes)

Kubemark creates "hollow nodes" that register with the API server but don't run actual workloads. Best for API server load testing.

### Setup Kubemark

```yaml
# kubemark-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kubemark
---
# kubemark-secret.yaml (create kubeconfig as secret)
apiVersion: v1
kind: Secret
metadata:
  name: kubeconfig
  namespace: kubemark
type: Opaque
data:
  kubeconfig: <base64-encoded-kubeconfig>
```

### Hollow Node Deployment

```yaml
# kubemark-hollow-nodes.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hollow-nodes
  namespace: kubemark
spec:
  replicas: 100  # Number of hollow nodes to simulate
  selector:
    matchLabels:
      name: hollow-node
  template:
    metadata:
      labels:
        name: hollow-node
    spec:
      containers:
      - name: hollow-kubelet
        image: registry.k8s.io/kubemark:v1.28.0
        args:
        - --morph=kubelet
        - --name=$(NODE_NAME)
        - --kubeconfig=/kubeconfig/kubeconfig
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        volumeMounts:
        - name: kubeconfig
          mountPath: /kubeconfig
          readOnly: true
        resources:
          requests:
            cpu: 20m
            memory: 50Mi
          limits:
            cpu: 100m
            memory: 100Mi
      volumes:
      - name: kubeconfig
        secret:
          secretName: kubeconfig
```

### Scale Hollow Nodes

```bash
# Scale to 500 hollow nodes
kubectl scale deployment hollow-nodes -n kubemark --replicas=500

# Verify nodes appear
kubectl get nodes | grep hollow
```

---

## Option 5: kube-burner for Load Testing

kube-burner is excellent for creating large numbers of Kubernetes objects quickly.

### Installation

```bash
# macOS
brew install kube-burner

# Linux
wget https://github.com/cloud-bulldozer/kube-burner/releases/latest/download/kube-burner-linux-x86_64.tar.gz
tar -xzf kube-burner-linux-x86_64.tar.gz
sudo mv kube-burner /usr/local/bin/
```

### Configuration for CAPI Clusters

```yaml
# kube-burner-config.yaml
global:
  writeToFile: true
  indexerConfig:
    enabled: false

jobs:
- name: create-simulated-clusters
  jobIterations: 1000
  qps: 50
  burst: 100
  namespacedIterations: false
  namespace: dm-dev-workspace
  objects:
  - objectTemplate: templates/cluster.yaml
    replicas: 1
```

```yaml
# templates/cluster.yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: sim-cluster-{{.Iteration}}
  namespace: {{.Namespace}}
  annotations:
    cluster.x-k8s.io/paused: "true"
    simulation: "true"
  labels:
    simulation: "true"
    iteration: "{{.Iteration}}"
spec:
  paused: true
  clusterNetwork:
    pods:
      cidrBlocks:
        - 192.168.0.0/16
    services:
      cidrBlocks:
        - 10.96.0.0/12
```

### Run kube-burner

```bash
# Create the namespace first
kubectl create namespace dm-dev-workspace 2>/dev/null || true

# Run kube-burner
kube-burner init -c kube-burner-config.yaml

# Cleanup
kubectl delete clusters -n dm-dev-workspace -l simulation=true
```

---

## Monitoring Scale Tests

### Watch Cluster Creation

```bash
# Watch cluster count
watch -n 1 "kubectl get clusters -n dm-dev-workspace --no-headers | wc -l"

# Watch with details
watch -n 2 "kubectl get clusters -n dm-dev-workspace -l simulation=true"
```

### API Server Metrics

```bash
# Check API server load
kubectl top pods -n kube-system | grep apiserver

# Check etcd performance
kubectl exec -n kube-system etcd-<node> -- etcdctl endpoint status --write-out=table
```

### Resource Usage

```bash
# Overall cluster resource usage
kubectl top nodes

# Specific namespace usage
kubectl top pods -n dm-dev-workspace --sum
```

---

## Best Practices

### 1. Start Small, Scale Up

```bash
# Test with 10 first
COUNT=10 ./generate-paused-clusters.sh

# Then scale up
COUNT=100 ./generate-paused-clusters.sh
COUNT=1000 ./generate-paused-clusters.sh
```

### 2. Use Batching

Always batch API calls to avoid overwhelming the API server:

```bash
BATCH_SIZE=50  # Adjust based on API server capacity
```

### 3. Monitor API Server Health

```bash
# Check API server response time
kubectl get --raw /healthz
kubectl get --raw /readyz

# Check request latency
kubectl get --raw /metrics | grep apiserver_request_duration
```

### 4. Cleanup Between Tests

```bash
# Always cleanup before new tests
kubectl delete clusters -n dm-dev-workspace -l simulation=true --wait=false
sleep 30  # Allow cleanup to complete
```

### 5. Resource Limits

Set resource limits on your management cluster:

```yaml
# Prevent runaway resource usage
apiVersion: v1
kind: ResourceQuota
metadata:
  name: scale-test-quota
  namespace: dm-dev-workspace
spec:
  hard:
    count/clusters.cluster.x-k8s.io: "2000"
```

---

## Troubleshooting

### API Server Throttling

If you see throttling errors:

```bash
# Reduce batch size
BATCH_SIZE=20 ./generate-paused-clusters.sh

# Add delays
sleep 0.1  # Between batches
```

### etcd Performance

If etcd is slow:

```bash
# Check etcd database size
kubectl exec -n kube-system etcd-<node> -- etcdctl endpoint status

# Compact and defrag if needed (CAREFUL in production!)
kubectl exec -n kube-system etcd-<node> -- etcdctl compact $(etcdctl endpoint status --write-out=json | jq -r '.header.revision')
kubectl exec -n kube-system etcd-<node> -- etcdctl defrag
```

### Memory Pressure

If nodes show memory pressure:

```bash
# Check node conditions
kubectl describe nodes | grep -A5 Conditions

# Reduce concurrent operations
BATCH_SIZE=10 ./generate-paused-clusters.sh
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Create 1000 paused clusters | `COUNT=1000 ./generate-paused-clusters.sh` |
| Create 100 KWOK clusters | `./create-kwok-clusters.sh 100` |
| Create 50 vclusters | `./create-vclusters.sh 50` |
| Count simulated clusters | `kubectl get clusters -n dm-dev-workspace -l simulation=true --no-headers \| wc -l` |
| Cleanup paused clusters | `kubectl delete clusters -n dm-dev-workspace -l simulation=true` |
| Cleanup KWOK clusters | `./cleanup-kwok-clusters.sh` |
| Cleanup vclusters | `./cleanup-vclusters.sh` |

---

## Additional Resources

- [KWOK Documentation](https://kwok.sigs.k8s.io/)
- [vcluster Documentation](https://www.vcluster.com/docs)
- [Kubemark Guide](https://github.com/kubernetes/kubernetes/tree/master/test/kubemark)
- [kube-burner Documentation](https://kube-burner.github.io/kube-burner/)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)

