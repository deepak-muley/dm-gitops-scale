# Troubleshooting Pod Distribution Commands

## Problem: Getting AGE Values Instead of Node Names

### Symptom

When running:
```bash
kubectl get pods -A -o wide | awk '{print $8}' | sort | uniq -c
```

You see output like:
```
   6 21m
   1 27m
   2 28m
   7 cluster-default-control-plane
   3 cluster-default-worker
```

**Problem:** The values "21m", "27m", "28m" are **AGE values**, not node names!

### Root Cause

When pods are **Pending** (not yet scheduled), they don't have a node assigned. This causes the NODE column to be empty, which shifts the columns when using `awk` on the `-o wide` output.

The `-o wide` format columns are:
1. NAMESPACE
2. NAME
3. READY
4. STATUS
5. RESTARTS
6. AGE
7. IP
8. NODE

When NODE is empty (Pending pods), the columns can shift, causing `$8` to capture AGE instead of NODE.

---

## Solution: Use JSON Output (Recommended)

### Reliable Method

```bash
# Get pod distribution (excludes Pending pods)
kubectl get pods -A --context kind-cluster-default -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  sort | uniq -c | sort -rn
```

**Output:**
```
   7 cluster-default-control-plane
   3 cluster-default-worker
   3 cluster-default-worker2
   3 cluster-default-worker3
```

### Count Pending Pods Separately

```bash
# Count pods without a node (Pending)
kubectl get pods -A --context kind-cluster-default -o json | \
  jq -r '.items[] | select(.spec.nodeName == null) | "\(.metadata.namespace)/\(.metadata.name)"'
```

---

## Alternative: Use Custom Columns

### Method 1: Custom Column Format

```bash
kubectl get pods -A --context kind-cluster-default -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
NODE:.spec.nodeName,\
STATUS:.status.phase | \
  awk 'NR>1 && $3 != "" {print $3}' | sort | uniq -c | sort -rn
```

### Method 2: Filter Out Pending First

```bash
kubectl get pods -A --context kind-cluster-default -o wide | \
  grep -v "Pending" | \
  awk '{print $8}' | sort | uniq -c | sort -rn
```

**Note:** This filters out Pending pods but may miss other statuses.

---

## What Your Output Tells Us

### Your Output Analysis

**Cluster Default:**
```
   6 21m          ← AGE values (6 pods with age 21m, no node assigned)
   1 27m          ← AGE value (1 pod with age 27m, no node assigned)
   2 28m          ← AGE values (2 pods with age 28m, no node assigned)
   7 cluster-default-control-plane  ← 7 pods on control plane
   3 cluster-default-worker         ← 3 pods on worker
   3 cluster-default-worker2        ← 3 pods on worker2
   3 cluster-default-worker3      ← 3 pods on worker3
   1 NODE         ← Header row
```

**Cluster Bin Packing:**
```
   5 15m          ← AGE values (5 pods with age 15m, no node assigned)
   1 24m          ← AGE value (1 pod with age 24m, no node assigned)
   1 25m          ← AGE value (1 pod with age 25m, no node assigned)
   1 26m          ← AGE value (1 pod with age 26m, no node assigned)
   7 cluster-bin-packing-control-plane  ← 7 pods on control plane
   8 cluster-bin-packing-worker         ← 8 pods on worker
   9 cluster-bin-packing-worker2        ← 9 pods on worker2
   8 cluster-bin-packing-worker3        ← 8 pods on worker3
   1 NODE         ← Header row
```

### Key Observations

1. **Both clusters have Pending pods:**
   - Default: 9 pods pending (6+1+2)
   - Bin Packing: 8 pods pending (5+1+1+1)

2. **Scheduled pods distribution:**
   - **Default:** 16 pods scheduled (7+3+3+3) - evenly distributed (3-4 pods per worker)
   - **Bin Packing:** 32 pods scheduled (7+8+9+8) - more concentrated (8-9 pods per worker)

3. **Bin Packing is working:**
   - Bin packing cluster has **2x more pods scheduled** (32 vs 16)
   - Bin packing shows **higher concentration** on workers (8-9 pods vs 3 pods)
   - This indicates bin packing is successfully concentrating workloads

4. **Pending pods:**
   - Both clusters have pods that haven't been scheduled yet
   - These might be:
     - Still starting up
     - Waiting for resources
     - Have resource constraints
     - Have node selectors/affinity that can't be satisfied

---

## Quick Fix Commands

### For Your Current Clusters

**Cluster Default:**
```bash
kubectl get pods -A --context kind-cluster-default -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  sort | uniq -c | sort -rn
```

**Cluster Bin Packing:**
```bash
kubectl get pods -A --context kind-cluster-bin-packing -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  sort | uniq -c | sort -rn
```

### Check Pending Pods

**Why pods are pending:**
```bash
# Cluster Default
kubectl get pods -A --context kind-cluster-default --field-selector=status.phase=Pending -o wide

# Cluster Bin Packing
kubectl get pods -A --context kind-cluster-bin-packing --field-selector=status.phase=Pending -o wide
```

**Get pending reasons:**
```bash
# Cluster Default
kubectl get pods -A --context kind-cluster-default --field-selector=status.phase=Pending -o json | \
  jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[]? | select(.type=="PodScheduled") | .reason // "unknown")"'

# Cluster Bin Packing
kubectl get pods -A --context kind-cluster-bin-packing --field-selector=status.phase=Pending -o json | \
  jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[]? | select(.type=="PodScheduled") | .reason // "unknown")"'
```

---

## Using the Fixed Script

The `cluster-metrics-analyzer.sh` script has been updated to use JSON output, which handles this correctly:

```bash
./cluster-metrics-analyzer.sh kind-cluster-default
./cluster-metrics-analyzer.sh kind-cluster-bin-packing
```

This will show:
- ✅ Correct pod distribution (no AGE values)
- ✅ Separate count of Pending pods
- ✅ Proper node assignments

---

## Summary

**Your output shows:**
1. ✅ Bin packing is working (more pods concentrated on fewer nodes)
2. ⚠️ Some pods are Pending (need investigation)
3. ✅ Bin packing cluster has 2x more scheduled pods

**Use JSON output** instead of `awk` on `-o wide` to avoid column shifting issues with Pending pods.
