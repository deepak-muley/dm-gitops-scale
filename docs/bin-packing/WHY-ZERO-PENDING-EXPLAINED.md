# Why Zero Pending Pods But Fewer Total Pods?

## The Question

When comparing clusters:
- **Cluster A**: 25 scheduled pods, 0 pending
- **Cluster B**: 31 scheduled pods, 0 pending

**Why does Cluster A have 0 pending pods but fewer total pods?**

---

## The Answer

**0 pending pods** means all pods that exist got scheduled. But **fewer total pods** means fewer pods were created in the first place.

### What's Happening

1. **Both clusters have 0 pending pods** → All existing pods got scheduled
2. **Cluster A has 25 total pods** → Only 25 pods exist
3. **Cluster B has 31 total pods** → 31 pods exist

**The difference:** Cluster A has **6 fewer pods created**, not 6 more pending.

---

## Why Fewer Pods Were Created?

### Possible Reasons

#### 1. **Deployments Didn't Create All Replicas**

Some deployments might not have created all requested replicas in Cluster A:

```bash
# Check deployment status
kubectl get deployments -A --context kind-cluster-default
kubectl get deployments -A --context kind-cluster-bin-packing

# Look for differences in READY/AVAILABLE columns
```

**Example:**
- Deployment requests 10 replicas
- Cluster A: Only 7 replicas created (READY: 7/10)
- Cluster B: All 10 replicas created (READY: 10/10)

#### 2. **Resource Constraints**

If Cluster A nodes are more evenly filled (default scheduler), there might be less room for new pods:

- Default scheduler spreads pods → All nodes partially used
- When a new pod needs resources, it might not find enough on any single node
- **Result:** Deployment controller doesn't create the pod (not pending, just not created)

#### 3. **Pod Eviction**

Some pods might have been evicted and not recreated:

```bash
# Check for evicted pods
kubectl get pods -A --context kind-cluster-default | grep Evicted

# Check pod status
kubectl get pods -A --context kind-cluster-default --field-selector=status.phase=Failed
```

#### 4. **Timing Differences**

If you checked Cluster A before all pods finished starting:
- Some pods might still be in "ContainerCreating" state
- They're scheduled but not fully started yet
- They count as "scheduled" but might not be fully ready

---

## How to Diagnose

### 1. Check Deployment Replica Counts

```bash
# Cluster A
kubectl get deployments -A --context kind-cluster-default \
  -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
DESIRED:.spec.replicas,\
CURRENT:.status.replicas,\
READY:.status.readyReplicas,\
AVAILABLE:.status.availableReplicas

# Cluster B
kubectl get deployments -A --context kind-cluster-bin-packing \
  -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
DESIRED:.spec.replicas,\
CURRENT:.status.replicas,\
READY:.status.readyReplicas,\
AVAILABLE:.status.availableReplicas
```

**Look for:**
- `DESIRED` vs `CURRENT` differences
- `CURRENT` vs `READY` differences
- `READY` vs `AVAILABLE` differences

### 2. Check Pod Status

```bash
# Cluster A - All pod phases
kubectl get pods -A --context kind-cluster-default \
  -o json | jq -r '.items | group_by(.status.phase) | .[] | "\(.[0].status.phase): \(length) pods"'

# Cluster B - All pod phases
kubectl get pods -A --context kind-cluster-bin-packing \
  -o json | jq -r '.items | group_by(.status.phase) | .[] | "\(.[0].status.phase): \(length) pods"'
```

**Phases to check:**
- `Running` - Pod is running
- `Pending` - Pod not scheduled yet
- `Failed` - Pod failed
- `Succeeded` - Pod completed successfully
- `Unknown` - Pod status unknown

### 3. Check Failed/Evicted Pods

```bash
# Cluster A
kubectl get pods -A --context kind-cluster-default \
  --field-selector=status.phase=Failed

# Check for evicted pods
kubectl get pods -A --context kind-cluster-default | grep Evicted
```

### 4. Check Node Resources

```bash
# Cluster A - Node resource availability
kubectl describe nodes --context kind-cluster-default | \
  grep -A 10 "Allocated resources"

# Cluster B - Node resource availability
kubectl describe nodes --context kind-cluster-bin-packing | \
  grep -A 10 "Allocated resources"
```

**Look for:**
- Nodes with very little free CPU/Memory
- Nodes that are nearly full
- Differences in resource distribution

### 5. Check Deployment Events

```bash
# Cluster A - Recent events
kubectl get events -A --context kind-cluster-default \
  --sort-by='.lastTimestamp' | tail -20

# Look for:
# - "FailedCreate" events
# - "FailedScheduling" events
# - Resource constraint messages
```

---

## Common Scenarios

### Scenario 1: Deployment Replicas Not Created

**Symptom:**
- Deployment shows `DESIRED: 10, CURRENT: 7`
- 3 pods never got created

**Cause:**
- Resource constraints
- Deployment controller couldn't create pods
- No suitable nodes available

**Solution:**
- Check node resources
- Check if bin packing would help (concentrates pods, leaves nodes free)

### Scenario 2: Pods Evicted

**Symptom:**
- Some pods show "Evicted" status
- Deployment shows fewer pods than desired

**Cause:**
- Node ran out of resources
- Kubelet evicted pods to free resources
- Pods not recreated if resources still constrained

**Solution:**
- Check node resource pressure
- Consider bin packing to better utilize resources

### Scenario 3: Timing Issue

**Symptom:**
- Checked Cluster A too early
- Some pods still starting

**Solution:**
- Wait a bit longer
- Check again after all pods have time to start

---

## Key Insight

**0 pending pods ≠ All pods created**

- **0 pending** means: All pods that exist got scheduled
- **Fewer total pods** means: Fewer pods were created in the first place

The difference is:
- **Pending pods**: Pods exist but can't be scheduled
- **Missing pods**: Pods never got created (deployment issue, resource constraints, etc.)

---

## What This Tells Us

### About Bin Packing

If Cluster B (bin packing) has more pods:
- ✅ Bin packing allows more pods to be created
- ✅ Better resource utilization enables more workloads
- ✅ Concentrated distribution leaves nodes free for new pods

### About Default Scheduler

If Cluster A (default) has fewer pods:
- ⚠️ Even distribution uses all nodes partially
- ⚠️ Less room for new pods
- ⚠️ Deployments might not create all replicas

---

## Summary

**Why 0 pending but fewer total pods?**

Because:
1. All existing pods got scheduled (0 pending)
2. But fewer pods were created in Cluster A
3. This could be due to:
   - Deployments not creating all replicas
   - Resource constraints preventing pod creation
   - Pod eviction
   - Timing differences

**Check deployment replica counts** to see if some replicas weren't created!

---

## Updated Scripts

The comparison scripts now show:
- ✅ Total pods count (all namespaces)
- ✅ Scheduled pods
- ✅ Pending pods
- ✅ Failed pods (if any)
- ✅ Deployment status checks
- ✅ Explanation of differences

Run:
```bash
../bin-packing/compare-clusters.sh kind-cluster-default kind-cluster-bin-packing
```

You'll now see a breakdown explaining why there are fewer total pods!
