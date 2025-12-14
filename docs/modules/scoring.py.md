# scoring.py - AEON Role Assignment Algorithm

## 📋 Overview

**File:** `lib/scoring.py`  
**Type:** Python script  
**Version:** 0.1.0  
**Purpose:** Assign manager/worker roles based on hardware capabilities

**Quick Description:**  
Analyzes hardware profiles and assigns optimal roles (manager/worker) ensuring managers have best hardware and proper count (3, 5, or 7).

---

## 🎯 Purpose

**Role Assignment Criteria:**

**Managers (need best hardware):**
- Higher RAM priority
- NVME storage preferred
- Active cooling preferred
- Gigabit network preferred
- PoE capability bonus

**Workers (remaining devices):**
- Can be less powerful
- Still functional for workloads

**Manager Count Rules:**
- Must be ODD (3, 5, or 7)
- For Raft consensus
- Fault tolerance: (N-1)/2

---

## 🚀 Usage

```bash
# Run from command line
python3 /opt/aeon/lib/scoring.py \
    /opt/aeon/data/hw_profiles.json \
    /opt/aeon/data/role_assignments.json

# Called by aeon-go.sh automatically
```

---

## 📊 Scoring Algorithm

### **Hardware Weights**

```python
scores = {
    "ram": ram_gb * 100,              # 8GB = 800 points
    "storage_type": {
        "nvme": 300,
        "ssd": 200,
        "sd": 100,
        "hdd": 150
    },
    "storage_size": size_gb,           # 512GB = 512 points
    "network": speed_mbps / 10,        # 1000Mbps = 100 points
    "cooling": 100 if active else 0,
    "poe": 50 if has_poe else 0
}

total_score = sum(scores)
```

---

### **Assignment Logic**

```
1. Filter: Raspberry Pis only
2. Score each Pi
3. Sort by score (descending)
4. Determine manager count:
   - 3-4 Pis → 3 managers
   - 5-6 Pis → 5 managers
   - 7+ Pis → 7 managers
5. Top N = managers
6. Remaining = workers
```

---

## 📚 Key Functions

### **score_device(device)**
Calculate score for single device.

**Returns:** Integer score

---

### **assign_roles(devices)**
Assign manager/worker roles.

**Returns:**
```json
{
  "assignments": [
    {
      "device": {...},
      "role": "manager",
      "score": 1850
    },
    {
      "device": {...},
      "role": "worker",
      "score": 1200
    }
  ],
  "summary": {
    "total_devices": 10,
    "managers": 3,
    "workers": 7
  }
}
```

---

## 📖 Example Output

```json
{
  "assignments": [
    {
      "device": {
        "ip": "192.168.1.101",
        "hostname": "pi5-master-01",
        "ram_gb": 8,
        "storage_type": "nvme",
        "storage_size_gb": 512
      },
      "role": "manager",
      "score": 1850,
      "rank": 1
    }
  ]
}
```

---

## 📊 Statistics

```
File: lib/scoring.py
Lines: ~600
Language: Python 3
Complexity: O(n log n) sorting
```

---

**Last Updated:** 2025-12-14
