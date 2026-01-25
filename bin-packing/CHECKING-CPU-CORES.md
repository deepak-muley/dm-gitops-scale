# Checking CPU Cores - Commands Reference

This document explains the commands used to find CPU cores in Kubernetes clusters and on your local machine.

---

## Commands Used in Scripts

### 1. Finding Total CPU Cores Across All Nodes (Kubernetes)

The scripts use this command to get total CPU capacity across all nodes:

```bash
kubectl get nodes --context <context> -o json | \
  jq -r '[.items[].status.capacity.cpu] | map(tonumber? // 0) | add'
```

**Breakdown:**
- `kubectl get nodes -o json` - Gets all nodes in JSON format
- `.items[].status.capacity.cpu` - Extracts CPU capacity from each node
- `map(tonumber? // 0)` - Converts to numbers (handles "4" or "4000m" format)
- `add` - Sums all values

**Example output:**
```
16
```

### 2. Finding Allocatable CPU (Available for Pods)

```bash
kubectl get nodes --context <context> -o json | \
  jq -r '[.items[].status.allocatable.cpu] | map(tonumber? // 0) | add'
```

**Difference:**
- `capacity.cpu` - Total CPU on the node
- `allocatable.cpu` - CPU available for pods (after system reservations)

### 3. Per-Node CPU Information

To see CPU per node:

```bash
kubectl get nodes --context <context> -o custom-columns=\
NAME:.metadata.name,\
CPU-CAPACITY:.status.capacity.cpu,\
CPU-ALLOCATABLE:.status.allocatable.cpu
```

**Example output:**
```
NAME                          CPU-CAPACITY   CPU-ALLOCATABLE
kind-cluster-default-worker   4              3950m
kind-cluster-default-worker2  4              3950m
kind-cluster-default-worker3  4              3950m
```

### 4. Detailed Node Information

```bash
kubectl describe node <node-name> --context <context>
```

Shows:
- Capacity (total resources)
- Allocatable (available for pods)
- Allocated resources (currently used)

---

## Finding CPU Cores on Your Desktop

### macOS

#### Method 1: Using `sysctl` (Recommended)
```bash
# Total physical CPU cores
sysctl -n hw.physicalcpu

# Total logical CPU cores (includes hyperthreading)
sysctl -n hw.logicalcpu

# Number of CPU packages (physical CPUs)
sysctl -n hw.packages

# CPU brand/model
sysctl -n machdep.cpu.brand_string
```

**Example output:**
```
$ sysctl -n hw.physicalcpu
8
$ sysctl -n hw.logicalcpu
16
$ sysctl -n machdep.cpu.brand_string
Apple M1 Pro
```

#### Method 2: Using `system_profiler`
```bash
system_profiler SPHardwareDataType | grep "Cores"
```

**Example output:**
```
      Chip: Apple M1 Pro
      Total Number of Cores: 10 (8 performance and 2 efficiency)
```

#### Method 3: Using `nproc` (if installed via Homebrew)
```bash
nproc
```

#### Method 4: Using Activity Monitor
- Open **Activity Monitor** (Applications > Utilities)
- Go to **Window** > **CPU History**
- Shows visual representation of CPU cores

### Linux

#### Method 1: Using `nproc` (Recommended)
```bash
# Total logical CPU cores
nproc

# Total physical CPU cores
nproc --all
```

#### Method 2: Using `/proc/cpuinfo`
```bash
# Count physical CPU cores
grep -c ^processor /proc/cpuinfo

# Or more accurately (handles hyperthreading)
lscpu | grep "^CPU(s):" | awk '{print $2}'

# Physical cores only
lscpu | grep "^Core(s) per socket" | awk '{print $4}'
```

#### Method 3: Using `lscpu` (Most Detailed)
```bash
lscpu
```

**Shows:**
- CPU(s): Total logical cores
- Thread(s) per core
- Core(s) per socket
- Socket(s): Number of physical CPUs

**Example output:**
```
CPU(s):                16
Thread(s) per core:    2
Core(s) per socket:    8
Socket(s):             1
```

#### Method 4: Using `getconf`
```bash
# Logical processors
getconf _NPROCESSORS_ONLN

# Or
getconf _NPROCESSORS_CONF
```

### Windows

#### Method 1: Using PowerShell
```powershell
# Total logical processors
(Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors

# Total physical processors
(Get-WmiObject Win32_ComputerSystem).NumberOfProcessors

# Or using newer cmdlet
(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
```

#### Method 2: Using Command Prompt
```cmd
wmic cpu get NumberOfCores,NumberOfLogicalProcessors
```

#### Method 3: Using System Information
- Press `Win + R`
- Type `msinfo32` and press Enter
- Look for "Processor" section

#### Method 4: Using Task Manager
- Press `Ctrl + Shift + Esc`
- Go to **Performance** tab
- Click **CPU**
- Shows "Cores" and "Logical processors"

---

## Understanding CPU Terminology

### Physical Cores vs Logical Cores

**Physical Cores:**
- Actual CPU cores on the chip
- Example: 8 physical cores

**Logical Cores:**
- Includes hyperthreading/SMT
- Example: 8 physical cores × 2 threads = 16 logical cores

**In Kubernetes:**
- Kubernetes counts logical cores
- A node with 8 physical cores (16 logical) shows as 16 cores

---

## Quick Reference Commands

### Kubernetes Cluster

```bash
# Total CPU capacity across all nodes
kubectl get nodes -o json | jq -r '[.items[].status.capacity.cpu] | map(tonumber? // 0) | add'

# Total allocatable CPU
kubectl get nodes -o json | jq -r '[.items[].status.allocatable.cpu] | map(tonumber? // 0) | add'

# Per-node breakdown
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu

# Detailed per-node info
kubectl describe nodes
```

### macOS Desktop

```bash
# Quick check
sysctl -n hw.logicalcpu

# Detailed info
sysctl hw.ncpu hw.physicalcpu hw.logicalcpu machdep.cpu.brand_string
```

### Linux Desktop

```bash
# Quick check
nproc

# Detailed info
lscpu
```

### Windows Desktop

```powershell
# Quick check
(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
```

---

## Examples

### Example 1: Kind Cluster (4 nodes, 4 cores each)

```bash
$ kubectl get nodes
NAME                          STATUS   ROLES           AGE   VERSION
kind-cluster-default-worker   Ready    <none>          5m    v1.35.0
kind-cluster-default-worker2  Ready    <none>          5m    v1.35.0
kind-cluster-default-worker3  Ready    <none>          5m    v1.35.0

$ kubectl get nodes -o json | jq -r '[.items[].status.capacity.cpu] | map(tonumber? // 0) | add'
12
```

**Result:** 12 total cores (3 nodes × 4 cores each)

### Example 2: macOS M1 Pro

```bash
$ sysctl -n hw.logicalcpu
10

$ sysctl -n hw.physicalcpu
10

$ sysctl -n machdep.cpu.brand_string
Apple M1 Pro
```

**Result:** 10 cores (8 performance + 2 efficiency)

### Example 3: Linux Server

```bash
$ nproc
16

$ lscpu | grep "^CPU(s):"
CPU(s):                16
```

**Result:** 16 logical cores

---

## CPU Format in Kubernetes

Kubernetes uses different formats for CPU:

- **Integer:** `4` = 4 cores
- **Millicores:** `4000m` = 4 cores
- **Decimal:** `4.5` = 4.5 cores

**Conversion:**
- 1 core = 1000m
- 0.5 core = 500m
- 2.5 cores = 2500m

The scripts handle this by using `tonumber?` which converts both formats.

---

## Troubleshooting

### Issue: Getting "0" or empty result

**Solution:** Check if nodes are accessible:
```bash
kubectl get nodes
kubectl get nodes -o json | jq '.items[0].status.capacity'
```

### Issue: CPU shows as "4000m" instead of "4"

**Solution:** The script handles both formats. If you need to convert:
```bash
# Convert millicores to cores
echo "4000m" | sed 's/m//' | awk '{print $1/1000}'
# Output: 4
```

### Issue: Different results on different systems

**Solution:** 
- macOS: Use `sysctl` (most reliable)
- Linux: Use `nproc` or `lscpu`
- Windows: Use PowerShell cmdlets

---

## Related Commands in Scripts

The comparison scripts use these commands:

1. **Total CPU Capacity:**
   ```bash
   kubectl get nodes --context "$context" -o json | \
     jq -r '[.items[].status.capacity.cpu] | map(tonumber? // 0) | add'
   ```

2. **Total Memory Capacity:**
   ```bash
   kubectl get nodes --context "$context" -o json | \
     jq -r '[.items[].status.capacity.memory] | map(gsub("[^0-9]"; "") | tonumber) | add'
   ```

3. **Allocatable Resources:**
   ```bash
   kubectl get nodes --context "$context" -o json | \
     jq -r '[.items[].status.allocatable.cpu] | map(tonumber? // 0) | add'
   ```

---

**See Also:**
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Node Capacity and Allocatable](https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/)
