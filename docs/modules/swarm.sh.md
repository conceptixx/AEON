![AEON Banner](/.github/assets/aeon_banner_v2_2400x600.png)

# swarm.sh - AEON Docker Swarm Setup Module

## 📋 Overview

**File:** `lib/swarm.sh`  
**Type:** Library module  
**Version:** 0.1.0  
**Purpose:** Initialize and configure Docker Swarm cluster

**Quick Description:**  
Creates Docker Swarm cluster with fault-tolerant manager quorum, joins workers, and configures overlay networks.

---

## 🎯 Purpose

**Docker Swarm provides:**
- Container orchestration
- Service deployment
- Load balancing
- Fault tolerance (with 3+ managers)
- Overlay networking

**AEON Swarm Architecture:**
- 3, 5, or 7 managers (ODD count for Raft)
- Remaining devices as workers
- Overlay network for inter-container communication

---

## 🚀 Usage

```bash
source /opt/aeon/lib/swarm.sh

# Initialize Swarm cluster
initialize_swarm_cluster \
    "$DATA_DIR/role_assignments.json" || exit 1

# Verify cluster health
verify_swarm_health || exit 1
```

---

## 🏗️ Architecture

```
initialize_swarm_cluster()
    │
    ├─> Select first manager (leader)
    ├─> Initialize Swarm on leader
    │     docker swarm init --advertise-addr <ip>
    │
    ├─> Get join tokens
    │     ├─> Manager token
    │     └─> Worker token
    │
    ├─> Join additional managers
    │     └─> For each manager (parallel)
    │           docker swarm join --token <manager-token>
    │
    └─> Join workers
          └─> For each worker (parallel)
                docker swarm join --token <worker-token>
```

---

## 📚 Key Functions

### **initialize_swarm_cluster(roles_json)**
Create Swarm cluster from role assignments.

**Steps:**
1. Initialize Swarm on first manager
2. Extract join tokens
3. Join remaining managers
4. Join workers
5. Create overlay network

**Returns:** 0 on success

---

### **get_swarm_join_tokens(leader_ip, user, password)**
Retrieve manager and worker join tokens.

**Returns:**
```json
{
  "manager": "SWMTKN-1-...-manager",
  "worker": "SWMTKN-1-...-worker"
}
```

---

### **join_as_manager(ip, user, password, leader_ip, token)**
Join device as Swarm manager.

---

### **join_as_worker(ip, user, password, leader_ip, token)**
Join device as Swarm worker.

---

### **verify_swarm_health()**
Check cluster is healthy.

**Verifies:**
- All managers in "Ready" state
- All workers joined
- Overlay network created
- Leader elected

**Example Output:**
```
✅ Swarm initialized
✅ 3 managers (all ready)
✅ 7 workers (all ready)
✅ Leader: pi5-master-01 (192.168.1.101)
```

---

## 📊 Statistics

```
File: lib/swarm.sh
Lines: ~650
Functions: 10
Initialization Time: 1-2 minutes
```

---

**Last Updated:** 2025-12-14
