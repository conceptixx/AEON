![AEON Banner](/.github/assets/aeon_banner_v2_2400x600.png)

# report.sh - AEON Cluster Report Generation Module

## 📋 Overview

**File:** `lib/report.sh`  
**Type:** Library module  
**Version:** 0.1.0  
**Purpose:** Generate comprehensive cluster documentation

**Quick Description:**  
Creates detailed cluster reports in Markdown, HTML, and JSON formats documenting all devices, roles, configurations, and status.

---

## 🎯 Purpose

**Report Contents:**
- Cluster topology
- Device inventory with hardware specs
- Role assignments (managers/workers)
- Docker Swarm status
- Network configuration
- Installation timestamp

**Output Formats:**
- `cluster_report.md` - Markdown (human-readable)
- `cluster_report.html` - HTML (browser-viewable)
- `cluster_report.json` - JSON (machine-parseable)

---

## 🚀 Usage

```bash
source /opt/aeon/lib/report.sh

# Generate all report formats
generate_cluster_report \
    "$DATA_DIR/hw_profiles.json" \
    "$DATA_DIR/role_assignments.json" \
    "$REPORT_DIR" || exit 1

# Reports saved to:
# - /opt/aeon/reports/cluster_report.md
# - /opt/aeon/reports/cluster_report.html
# - /opt/aeon/reports/cluster_report.json
```

---

## 📚 Key Functions

### **generate_cluster_report(hw_file, roles_file, output_dir)**
Generate all report formats.

**Returns:** 0 on success

---

### **generate_markdown_report()**
Create Markdown report.

**Sections:**
- Cluster summary
- Manager nodes table
- Worker nodes table
- Hardware specifications
- Network topology

---

### **generate_html_report()**
Convert Markdown to HTML with styling.

---

### **generate_json_report()**
Machine-readable JSON export.

---

## 📊 Example Report

```markdown
# AEON Cluster Report

Generated: 2025-12-14 15:30:45

## Cluster Summary
- Total Devices: 10
- Managers: 3
- Workers: 7
- Total RAM: 64GB
- Total Storage: 5TB

## Manager Nodes
| IP | Hostname | RAM | Storage |
|----|----------|-----|---------|
| 192.168.1.101 | pi5-master-01 | 8GB | 512GB |
| 192.168.1.102 | pi5-master-02 | 8GB | 512GB |
| 192.168.1.103 | pi5-master-03 | 8GB | 512GB |
```

---

## 📊 Statistics

```
File: lib/report.sh
Lines: ~700
Functions: 8
Formats: Markdown, HTML, JSON
```

---

**Last Updated:** 2025-12-14
