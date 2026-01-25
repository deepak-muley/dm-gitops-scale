# What to Expect: Bin Packing Scripts Guide

This document explains what happens when you run the bin packing scripts and what you should expect to see.

---

## Script 1: `bin-packing-kind-setup.sh`

### Purpose
Creates a local kind (Kubernetes in Docker) cluster with resource bin packing enabled for demonstration and learning.

**For a complete end-to-end demonstration with Prometheus/Grafana and detailed utilization analysis, see:**
- **[`bin-packing-e2e-demo.sh`](../bin-packing/bin-packing-e2e-demo.sh)** - Complete E2E demo with metrics and explanations
- **[Bin Packing Utilization Explained](./BIN-PACKING-UTILIZATION-EXPLAINED.md)** - Detailed explanation of utilization improvements

### What It Does

1. **Creates a kind cluster** with 1 control plane and 3 worker nodes
2. **Applies bin packing scheduler configuration** after cluster is ready
3. **Installs metrics-server** for resource metrics (enables `kubectl top`)
4. **Deploys a test workload** (15 nginx pods) to demonstrate bin packing behavior
5. **Shows pod distribution** across nodes
6. **Optionally installs kube-prometheus-stack** as an example platform service

### Expected Output

#### During Execution

```
════════════════════════════════════════════════════════════════
  Kubernetes Resource Bin Packing - Kind Cluster Setup
════════════════════════════════════════════════════════════════

Cluster Name: bin-packing-demo
Strategy: mostallocated

Creating scheduler configuration for mostallocated strategy...
✓ Scheduler configuration file created
Creating kind cluster configuration...
Creating kind cluster (this may take a few minutes)...
✓ Cluster is ready!
Waiting for nodes to be ready...
✓ Nodes are ready
Applying scheduler configuration with mostallocated strategy...
Copying scheduler config to control plane node...
✓ Scheduler config file copied
Modifying scheduler static pod manifest...
✓ Scheduler restarted with bin packing enabled
Installing metrics-server...
✓ Metrics-server installed
Creating test deployment to demonstrate bin packing...
Waiting for pods to be scheduled...

Install kube-prometheus-stack as example platform service? (y/n) y
Installing kube-prometheus-stack with bin packing enabled...
✓ kube-prometheus-stack installed
```

#### Final Results

You should see output like:

```
════════════════════════════════════════════════════════════════
  Results: Pod Distribution Across Nodes
════════════════════════════════════════════════════════════════

NAME                              READY   STATUS    NODE
bin-packing-test-xxx-1            1/1     Running   bin-packing-demo-worker
bin-packing-test-xxx-2            1/1     Running   bin-packing-demo-worker
bin-packing-test-xxx-3            1/1     Running   bin-packing-demo-worker
bin-packing-test-xxx-4            1/1     Running   bin-packing-demo-worker
bin-packing-test-xxx-5            1/1     Running   bin-packing-demo-worker
bin-packing-test-xxx-6            1/1     Running   bin-packing-demo-worker2
bin-packing-test-xxx-7            1/1     Running   bin-packing-demo-worker2
bin-packing-test-xxx-8            1/1     Running   bin-packing-demo-worker2
bin-packing-test-xxx-9            1/1     Running   bin-packing-demo-worker2
bin-packing-test-xxx-10           1/1     Running   bin-packing-demo-worker2
bin-packing-test-xxx-11           1/1     Running   bin-packing-demo-worker3
bin-packing-test-xxx-12           1/1     Running   bin-packing-demo-worker3
bin-packing-test-xxx-13           1/1     Running   bin-packing-demo-worker3
bin-packing-test-xxx-14           1/1     Running   bin-packing-demo-worker3
bin-packing-test-xxx-15           1/1     Running   bin-packing-demo-worker3

Pod count per node:
   5 bin-packing-demo-worker
   5 bin-packing-demo-worker2
   5 bin-packing-demo-worker3
```

### What This Means

**With Bin Packing (MostAllocated):**
- ✅ Pods are **concentrated** on fewer nodes
- ✅ Higher node utilization (60-80% typical)
- ✅ Fewer nodes used overall
- ✅ Better resource efficiency

**Expected Pattern:**
- Most pods on 2-3 nodes (not evenly spread)
- Some nodes may have 0 pods
- Higher CPU/memory usage on nodes with pods

### Verification Steps

After the script completes, verify bin packing is working:

```bash
# 1. Check scheduler is using bin packing config
kubectl logs -n kube-system --context kind-bin-packing-demo \
  -l component=kube-scheduler | grep -i "mostallocated\|bin\|pack"

# 2. Check pod distribution (should be uneven)
# For single namespace, node is column 7; for -A (all namespaces), node is column 8
kubectl get pods --context kind-bin-packing-demo -o wide | \
  awk '{print $7}' | sort | uniq -c | sort -rn
# OR for all namespaces:
kubectl get pods -A --context kind-bin-packing-demo -o wide | \
  awk '{print $8}' | sort | uniq -c | sort -rn

# 3. Check node resource utilization (metrics-server now installed)
kubectl top nodes --context kind-bin-packing-demo
kubectl top pods --context kind-bin-packing-demo

# 4. If Prometheus was installed, check its pod distribution
kubectl get pods -n monitoring --context kind-bin-packing-demo -o wide
kubectl get pods -n monitoring --context kind-bin-packing-demo -o wide --no-headers | \
  awk '{print $7}' | sort | uniq -c | sort -rn
# Note: For single namespace, node is column 7; for -A, node is column 8

# 5. Deploy more pods and watch them concentrate
kubectl scale deployment bin-packing-test --replicas=30 \
  --context kind-bin-packing-demo
kubectl get pods --context kind-bin-packing-demo -o wide -w
```

### Cluster Persistence

**Important:** The cluster **remains running** after the script completes. It will NOT be automatically deleted.

**To delete the cluster later:**
```bash
kind delete cluster --name bin-packing-demo
```

**To keep using the cluster:**
```bash
# Set context
kubectl config use-context kind-bin-packing-demo

# Continue testing
kubectl get nodes
kubectl get pods -A
```

---

## Script 2: `nkp-platform-bin-packing.sh`

### Purpose
Applies resource bin packing configuration to a **real Nutanix NKP (Nutanix Kubernetes Platform) management cluster** to increase density of platform services.

### What It Does

1. **Enables bin packing scheduler profile** for platform services
2. **Creates/updates scheduler ConfigMap** with bin packing configuration
3. **Restarts kube-scheduler** to apply changes
4. **Provides status and testing capabilities**

### Usage Options

#### 1. Enable Bin Packing

```bash
./nkp-platform-bin-packing.sh enable
```

**Expected Output:**
```
════════════════════════════════════════════════════════════════
  NKP Platform Services - Resource Bin Packing
════════════════════════════════════════════════════════════════

Action: Enable bin packing for platform services

Backing up current scheduler configuration...
✓ Backup saved
Creating scheduler configuration...
Restarting kube-scheduler...
Waiting for scheduler to be ready...
✓ Bin packing enabled for platform services

Note: Platform services need to specify 
schedulerName: platform-services to use the bin packing profile.
```

**What Happens:**
- ✅ Creates `kube-scheduler-config` ConfigMap in `kube-system` namespace
- ✅ Configures two scheduler profiles:
  - `platform-services`: Uses `RequestedToCapacityRatio` with bin packing
  - `default-scheduler`: Uses `LeastAllocated` (spread pods)
- ✅ Restarts kube-scheduler deployment
- ✅ Creates backup of original config (timestamped)

#### 2. Check Status

```bash
./nkp-platform-bin-packing.sh status
```

**Expected Output:**
```
════════════════════════════════════════════════════════════════
  NKP Platform Services - Resource Bin Packing
════════════════════════════════════════════════════════════════

Action: Show bin packing status

Scheduler Configuration:
✓ Custom scheduler config exists
  → Bin packing strategy detected

Scheduler Status:
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
kube-scheduler    1/1     1            1           5d

Platform Service Pod Distribution:

Namespace: kommander (45 pods)
  Pods per node:
    node-1: 15 pods
    node-2: 18 pods
    node-3: 12 pods

Namespace: cert-manager (3 pods)
  Pods per node:
    node-1: 2 pods
    node-2: 1 pod

Node Resource Utilization:
NAME      CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
node-1    8.5          65%    24Gi           70%
node-2    9.2          71%    26Gi           76%
node-3    7.1          55%    20Gi           58%
```

**What This Shows:**
- ✅ Whether bin packing is enabled
- ✅ Scheduler deployment status
- ✅ Current pod distribution across nodes
- ✅ Node resource utilization

#### 3. Test Bin Packing

```bash
./nkp-platform-bin-packing.sh test
```

**Expected Output:**
```
Action: Test bin packing behavior

Creating test deployment with bin packing scheduler...
Waiting for pods to be scheduled...

Pod distribution:
NAME                          NODE
bin-packing-test-xxx-1        node-1
bin-packing-test-xxx-2        node-1
bin-packing-test-xxx-3        node-1
bin-packing-test-xxx-4        node-1
bin-packing-test-xxx-5        node-1
bin-packing-test-xxx-6        node-2
bin-packing-test-xxx-7        node-2
bin-packing-test-xxx-8        node-2
bin-packing-test-xxx-9        node-2
bin-packing-test-xxx-10       node-2

Pods per node:
   5 node-1
   5 node-2
```

**What This Does:**
- ✅ Creates a test namespace `nkp-bin-packing-test`
- ✅ Deploys 10 test pods with `schedulerName: platform-services`
- ✅ Shows pod distribution (should concentrate on fewer nodes)
- ✅ Optionally cleans up test deployment

#### 4. Disable Bin Packing

```bash
./nkp-platform-bin-packing.sh disable
```

**Expected Output:**
```
Action: Disable bin packing (restore default)

Restoring from backup: scheduler-backup-20260125-015630.yaml
Restarting kube-scheduler...
Waiting for scheduler to be ready...
✓ Bin packing disabled (default scheduler restored)
```

**What Happens:**
- ✅ Restores original scheduler configuration from backup
- ✅ Removes bin packing profile
- ✅ Restarts scheduler with default configuration

---

## Expected Behavior Comparison

### Before Bin Packing (Default - LeastAllocated)

```
Platform Services Pod Distribution:
  node-1: 8 pods  (30% CPU, 40% Memory)
  node-2: 9 pods  (32% CPU, 42% Memory)
  node-3: 8 pods  (28% CPU, 38% Memory)
  node-4: 7 pods  (25% CPU, 35% Memory)
  node-5: 6 pods  (22% CPU, 33% Memory)

Total: 38 pods across 5 nodes
Average utilization: ~28% CPU, ~38% Memory
```

### After Bin Packing (MostAllocated/RequestedToCapacityRatio)

```
Platform Services Pod Distribution:
  node-1: 15 pods (68% CPU, 75% Memory)
  node-2: 14 pods (65% CPU, 72% Memory)
  node-3: 9 pods  (42% CPU, 48% Memory)
  node-4: 0 pods (0% CPU, 0% Memory)
  node-5: 0 pods (0% CPU, 0% Memory)

Total: 38 pods across 3 nodes (2 nodes freed up)
Average utilization: ~58% CPU, ~65% Memory
```

### Benefits

✅ **40-50% reduction** in nodes needed for platform services  
✅ **Higher resource utilization** (60-70% vs 30-40%)  
✅ **More nodes available** for workloads  
✅ **Lower infrastructure costs**  
✅ **Better ROI** on infrastructure  

---

## Applying Bin Packing to Platform Services

After enabling bin packing, platform services need to specify the scheduler profile:

### Option 1: Update Existing Deployments

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: kommander
spec:
  template:
    spec:
      schedulerName: platform-services  # Use bin packing scheduler
      containers:
      - name: prometheus
        # ... container spec
```

### Option 2: Use Helm Values

```yaml
# values.yaml
schedulerName: platform-services
```

### Option 3: Use Kustomize

```yaml
# kustomization.yaml
patches:
- patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: prometheus
    spec:
      template:
        spec:
          schedulerName: platform-services
  target:
    kind: Deployment
    name: prometheus
```

---

## Monitoring and Verification

### Check Scheduler Configuration

```bash
# Verify ConfigMap exists
kubectl get configmap kube-scheduler-config -n kube-system -o yaml

# Check scheduler logs
kubectl logs -n kube-system -l component=kube-scheduler --tail=50 | \
  grep -i "bin\|pack\|most\|allocated"
```

### Monitor Pod Distribution

```bash
# Watch pod distribution over time
watch -n 5 'kubectl get pods -n kommander -o wide | \
  awk "{print \$7}" | sort | uniq -c | sort -rn'
```

### Check Node Utilization

```bash
# Monitor node resource usage
kubectl top nodes

# Detailed node info
kubectl describe nodes | grep -A 10 "Allocated resources"
```

### Verify Bin Packing is Working

**Signs bin packing is working:**
- ✅ Pods concentrate on fewer nodes
- ✅ Some nodes have 0 pods
- ✅ Node utilization is 60-80% on nodes with pods
- ✅ Scheduler logs show bin packing strategy

**Signs bin packing is NOT working:**
- ❌ Pods spread evenly across all nodes
- ❌ All nodes have similar pod counts
- ❌ Node utilization is 30-40% across all nodes
- ❌ Scheduler logs don't mention bin packing

---

## Troubleshooting

### Issue: Pods Still Spreading Evenly

**Possible Causes:**
1. Services not using `schedulerName: platform-services`
2. Pod anti-affinity rules forcing spread
3. Node selectors/taints limiting placement
4. Resource requests too large for bin packing

**Solution:**
```bash
# Check if services specify schedulerName
kubectl get deployments -n kommander -o yaml | grep schedulerName

# Check for pod anti-affinity
kubectl get deployments -n kommander -o yaml | grep -A 10 antiAffinity
```

### Issue: Scheduler Not Restarting

**Solution:**
```bash
# Manually restart scheduler
kubectl rollout restart deployment/kube-scheduler -n kube-system

# Check scheduler status
kubectl get deployment kube-scheduler -n kube-system
kubectl get pods -n kube-system -l component=kube-scheduler
```

### Issue: High Resource Contention

**Solution:**
- Monitor for OOMKilled pods: `kubectl get events | grep OOMKilled`
- Check CPU throttling: `kubectl top pods`
- Adjust resource requests/limits
- Consider reducing bin packing aggressiveness

---

## Best Practices

1. **Start with Non-Critical Services**
   - Test with Kubernetes Dashboard, Grafana first
   - Then apply to observability stack
   - Finally apply to critical services

2. **Monitor Closely**
   - Watch for 1-2 weeks after enabling
   - Set up alerts for resource contention
   - Monitor pod restart rates

3. **Use Pod Disruption Budgets**
   - Ensure HA despite bin packing
   - Set appropriate minAvailable values

4. **Regular Review**
   - Review node utilization monthly
   - Adjust resource requests quarterly
   - Re-evaluate as cluster grows

---

## Summary

### Kind Cluster Script (`bin-packing-kind-setup.sh`)
- ✅ Creates local test cluster
- ✅ Installs metrics-server for resource monitoring
- ✅ Demonstrates bin packing behavior with test workload
- ✅ Optionally installs kube-prometheus-stack as example platform service
- ✅ Cluster persists after script completes
- ✅ Use for learning and testing
- ✅ See `examples/prometheus-bin-packing-example.yaml` for Prometheus configuration

### E2E Demonstration Script (`bin-packing-e2e-demo.sh`)
- ✅ Complete end-to-end demonstration
- ✅ Automatically installs Prometheus, Grafana, Alertmanager
- ✅ Deploys multiple test workloads
- ✅ Shows detailed utilization metrics and analysis
- ✅ Explains how bin packing improves utilization
- ✅ Provides access information for Grafana/Prometheus
- ✅ Best for understanding the full impact of bin packing

**Recommended:** Start with `bin-packing-e2e-demo.sh` for the complete experience!

### NKP Platform Script (`nkp-platform-bin-packing.sh`)
- ✅ Applies to real NKP management cluster
- ✅ Enables bin packing for platform services
- ✅ Provides status and testing tools
- ✅ Use for production optimization

Both scripts work together to help you understand and implement resource bin packing in your Kubernetes environments.
