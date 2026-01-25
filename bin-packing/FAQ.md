# Frequently Asked Questions

## Cluster Management

### Q: Do I need to delete existing clusters before running the comparison script?

**A: No, the script handles this automatically!**

The `bin-packing-comparison.sh` script will:
- ✅ Check for existing clusters with the same names
- ✅ Automatically delete them before creating new ones
- ✅ Warn you if clusters exist and will be deleted

**Cluster names used:**
- `cluster-default` (Cluster A - default scheduler)
- `cluster-bin-packing` (Cluster B - bin packing scheduler)

**If you have clusters with different names:**
- They won't be affected
- Only clusters with the exact names above will be deleted

**To manually check/delete:**
```bash
# List all kind clusters
kind get clusters

# Delete specific cluster
kind delete cluster --name cluster-default
kind delete cluster --name cluster-bin-packing
```

---

### Q: What if I have a cluster named `bin-packing-demo` from the E2E script?

**A: It won't be affected!**

The comparison script uses different cluster names:
- Comparison script: `cluster-default` and `cluster-bin-packing`
- E2E script: `bin-packing-demo`

They won't conflict. You can have both running simultaneously.

---

### Q: Can I keep the clusters after the comparison script finishes?

**A: Yes!**

When the script finishes, it will ask:
```
Keep clusters running for further exploration? (y/n)
```

- Answer `y` to keep both clusters running
- Answer `n` to delete them automatically

If you keep them, delete manually later:
```bash
kind delete cluster --name cluster-default
kind delete cluster --name cluster-bin-packing
```

---

## Resource Requirements

### Q: How much RAM do I need for the comparison script?

**A: ~8GB RAM recommended**

The comparison script creates 2 clusters simultaneously:
- Each cluster: ~4GB RAM
- Total: ~8GB RAM

**Minimum:** 6GB RAM (may be slow)
**Recommended:** 8GB+ RAM

---

### Q: Can I run it on a machine with limited resources?

**A: Yes, but with modifications**

Options:
1. **Run clusters sequentially** (modify script to create one at a time)
2. **Reduce node count** (change from 3 workers to 2 workers)
3. **Skip Prometheus installation** (just compare test workloads)

---

## Script Behavior

### Q: What happens if the script fails partway through?

**A: The script has cleanup handling**

- If script exits normally: Clusters deleted (unless you chose to keep them)
- If script crashes: Clusters may remain (delete manually)
- If interrupted (Ctrl+C): Clusters remain for exploration

**To clean up manually:**
```bash
kind delete cluster --name cluster-default
kind delete cluster --name cluster-bin-packing
```

---

### Q: Can I run the comparison script multiple times?

**A: Yes!**

The script will:
- Delete existing clusters with same names
- Create fresh clusters
- Install everything from scratch

Each run gives you a clean comparison.

---

## Understanding Results

### Q: Why do the metrics vary between runs?

**A: This is normal!**

Factors that affect results:
- **Timing:** Metrics collected at different times
- **Resource availability:** Node capacity varies slightly
- **Scheduling decisions:** Scheduler makes decisions based on current state
- **Pod startup time:** Pods start at slightly different times

**The key is the pattern, not exact numbers:**
- Default: Even distribution
- Bin Packing: Concentrated distribution

---

### Q: What if both clusters show similar distribution?

**A: Check a few things:**

1. **Verify bin packing is enabled:**
   ```bash
   kubectl logs -n kube-system --context kind-cluster-bin-packing \
     -l component=kube-scheduler | grep -i "mostallocated"
   ```

2. **Check resource requests:**
   - If requests are too large, pods can't pack tightly
   - If requests are too small, distribution may look similar

3. **Wait longer:**
   - Pods may still be scheduling
   - Metrics need time to stabilize

4. **Check node capacity:**
   ```bash
   kubectl describe nodes --context kind-cluster-bin-packing | grep Capacity
   ```

---

## Troubleshooting

### Q: Script hangs when creating clusters

**A: Check Docker and resources:**

```bash
# Check Docker is running
docker ps

# Check Docker resources
docker system df

# Free up space if needed
docker system prune

# Check if ports are in use
lsof -i :6443  # Kubernetes API
```

---

### Q: Prometheus installation fails or times out

**A: This is common with limited resources:**

The script will continue even if Prometheus times out. You can:
1. **Install manually later:**
   ```bash
   helm install prometheus prometheus-community/kube-prometheus-stack \
     -n monitoring --create-namespace \
     --kube-context kind-cluster-default
   ```

2. **Skip Prometheus** (modify script to comment out `install_prometheus_both`)

3. **Reduce Prometheus resources** in values file

---

### Q: Metrics not showing (`kubectl top` returns nothing)

**A: Wait for metrics-server to collect data:**

```bash
# Check metrics-server is running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Wait 30-60 seconds after deployments
sleep 30
kubectl top nodes

# Check metrics-server logs if still not working
kubectl logs -n kube-system -l k8s-app=metrics-server
```

---

## Best Practices

### Q: Should I run comparison or E2E demo first?

**A: Depends on your goal:**

- **Comparison script:** Best for seeing real differences with proof
- **E2E demo:** Best for learning with detailed explanations

**Recommended order:**
1. Run E2E demo first (learn the concepts)
2. Run comparison script (see real proof)
3. Apply to your NKP cluster (production use)

---

### Q: How long does the comparison take?

**A: ~15-20 minutes**

Breakdown:
- Cluster A creation: ~3-5 minutes
- Cluster B creation: ~3-5 minutes
- Prometheus installation: ~5-8 minutes (both clusters)
- Workload deployment: ~2-3 minutes
- Metrics collection: ~1-2 minutes

**Total: ~15-20 minutes**

---

## Advanced Usage

### Q: Can I modify the workloads or applications?

**A: Yes!**

Edit the script:
- Change workload replicas in `deploy_workloads()`
- Modify Prometheus values in `install_prometheus_both()`
- Add more applications to both clusters

**Make sure to apply same changes to both clusters for fair comparison!**

---

### Q: Can I compare different bin packing strategies?

**A: Yes!**

Modify the script to create Cluster B with different strategy:
```bash
# Change from mostallocated to requestedtocapacityratio
STRATEGY="requestedtocapacityratio"
```

Or create Cluster C with a third strategy for 3-way comparison.

---

## Still Have Questions?

- Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- Review [COMPARISON-GUIDE.md](./COMPARISON-GUIDE.md)
- See [WHAT-TO-EXPECT.md](./WHAT-TO-EXPECT.md)
