# Bin Packing Script Troubleshooting

## Common Issues

### Issue: Scheduler Fails to Start

**Symptoms:**
- Cluster creation succeeds but scheduler never becomes healthy
- Error: `kube-scheduler check failed at https://127.0.0.1:10259/livez: connection refused`

**Root Cause:**
The scheduler configuration file wasn't accessible during cluster bootstrap when using the mount approach.

**Solution:**
The script now uses a post-creation approach:
1. Creates the cluster normally
2. Copies the scheduler config file to the control plane node
3. Modifies the static pod manifest directly
4. Kubelet automatically restarts the scheduler with the new config

**If you still see issues:**
```bash
# Check scheduler pod status
kubectl get pods -n kube-system -l component=kube-scheduler

# Check scheduler logs
kubectl logs -n kube-system -l component=kube-scheduler

# Verify config file exists on node
docker exec bin-packing-demo-control-plane cat /etc/kubernetes/scheduler-config.yaml

# Check static pod manifest
docker exec bin-packing-demo-control-plane cat /etc/kubernetes/manifests/kube-scheduler.yaml
```

### Issue: Script Hangs on `kind get clusters`

**Symptoms:**
- Script hangs when checking for existing clusters
- No output for extended period

**Solution:**
The script now includes a timeout. If it still hangs:
```bash
# Check if Docker is running
docker ps

# Check kind directly
kind get clusters

# Manually delete stuck cluster
kind delete cluster --name bin-packing-demo
```

### Issue: Permission Errors with kubeconfig

**Symptoms:**
- `failed to lock config file: operation not permitted`
- Permission denied errors

**Solution:**
```bash
# Fix kubeconfig permissions
chmod 600 ~/.kube/config

# Remove lock file if stuck
rm -f ~/.kube/config.lock

# Ensure you have write access
ls -la ~/.kube/
```

### Issue: Scheduler Config Not Applied

**Symptoms:**
- Cluster runs but pods still spread evenly (no bin packing)

**Diagnosis:**
```bash
# Check if scheduler is using custom config
kubectl logs -n kube-system -l component=kube-scheduler | grep -i config

# Verify config file content on node
docker exec bin-packing-demo-control-plane cat /etc/kubernetes/scheduler-config.yaml

# Check scheduler command line args
docker exec bin-packing-demo-control-plane cat /etc/kubernetes/manifests/kube-scheduler.yaml | grep -A 10 command
```

**Solution:**
If config is not being used, manually verify:
1. Config file exists: `/etc/kubernetes/scheduler-config.yaml` on control plane node
2. Manifest includes `--config=/etc/kubernetes/scheduler-config.yaml` in command
3. Scheduler pod restarted after changes

### Issue: Docker/Container Runtime Issues

**Symptoms:**
- Cannot copy files to node
- Cannot exec into container

**Solution:**
```bash
# Verify Docker is running
docker ps

# Check if kind nodes are running
docker ps | grep kind

# Restart Docker if needed (macOS/Linux)
sudo systemctl restart docker  # Linux
# or restart Docker Desktop on macOS
```

## Manual Recovery Steps

If the script fails partway through:

1. **Clean up:**
   ```bash
   kind delete cluster --name bin-packing-demo
   ```

2. **Verify cleanup:**
   ```bash
   docker ps | grep bin-packing
   # Should be empty
   ```

3. **Re-run script:**
   ```bash
   ../bin-packing/bin-packing-kind-setup.sh mostallocated
   ```

## Alternative: Use Real Kubernetes Cluster

If kind continues to have issues, you can apply bin packing to a real Kubernetes cluster using the NKP script:

```bash
./nkp-platform-bin-packing.sh enable
```

This works with any Kubernetes cluster, not just NKP.

## Getting Help

If issues persist:
1. Check scheduler logs: `kubectl logs -n kube-system -l component=kube-scheduler`
2. Check node status: `kubectl get nodes`
3. Verify Docker/kind versions are up to date
4. Review the [Kubernetes scheduler documentation](https://kubernetes.io/docs/reference/scheduling/config/)
