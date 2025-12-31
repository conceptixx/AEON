# AEON Nexus - Installation & Setup

## 📦 Paket-Inhalt

```
aeon_nexus_prototype/
├── Core System
│   ├── nexus_daemon.py          # Universal Daemon (400 LOC)
│   ├── start.py                 # Bootstrap Entry Point
│   ├── nexus_config.json        # Configuration
│   │
│   ├── core/
│   │   ├── heartbeat.py         # Heartbeat Sender
│   │   └── __init__.py
│   │
│   └── roles/
│       ├── watchdog.py          # Watchdog Role (Heartbeat Monitor)
│       └── __init__.py
│
├── Monitoring & Testing
│   ├── monitor.sh               # Simple Monitor
│   ├── monitor_live.sh          # Enhanced Live Monitor
│   ├── test.sh                  # Basic System Test
│   ├── test_heartbeat.sh        # Heartbeat + Auto-Restart Test
│   └── chaos_test.py            # Chaos Engineering Test
│
├── Control
│   └── stop.sh                  # Graceful Shutdown
│
└── Documentation
    ├── README.md                # Hauptdokumentation
    ├── QUICKSTART.md            # 2-Terminal Setup Guide
    └── LOAD_BALANCING.md        # Future Load-Balancing Architektur
```

**Gesamt:** 1,267 Zeilen Code | ZIP: ~30 KB

---

## 🚀 Installation

### 1. Entpacken

```bash
# Entpacken
unzip aeon_nexus_prototype.zip

# In das Verzeichnis wechseln
cd aeon_nexus_prototype

# Permissions setzen
chmod +x *.py *.sh
```

### 2. Voraussetzungen

**Minimal:**
- Python 3.7+
- Linux/Unix (getestet auf Ubuntu 24)
- Keine zusätzlichen pip-Dependencies! ✅

**Empfohlen für Tests:**
- 2 Terminal-Fenster
- `watch` command (für Live-Monitoring)

### 3. Verifikation

```bash
# Python-Version prüfen
python3 --version  # Sollte >= 3.7 sein

# Test-Run
./test.sh
```

---

## ⚡ Quick Start

### Option 1: Schneller Test (20 Sekunden)

```bash
./test_heartbeat.sh
```

**Was wird getestet:**
- Cluster Startup (10 Daemons)
- Heartbeat-System (3 Watchdogs)
- Daemon Kill (simuliert Failure)
- Auto-Restart (durch Watchdogs)

### Option 2: Live Demo (2 Terminals)

**Terminal 1: Monitor**
```bash
./start.py &
sleep 5
watch -n 1 ./monitor_live.sh
```

**Terminal 2: Chaos Test**
```bash
./chaos_test.py --duration 60
```

**Siehe:** `QUICKSTART.md` für Details

---

## 📁 Wichtige Dateien

### Konfiguration
- `nexus_config.json` - Daemon-Counts anpassen

```json
{
  "daemons": {
    "communicators": 2,    # Leader-Daemons
    "watchdogs": 3,        # Heartbeat-Monitore
    "workflows": 5         # Worker-Daemons
  }
}
```

### Runtime
- `/tmp/nexus/` - Socket-Files & Runtime-Data
- `control.sock` - Master-Socket
- `heartbeat_*.sock` - Watchdog-Sockets (3x)

---

## 🛠️ Verwendung

### Starten
```bash
./start.py
```

### Monitoring
```bash
# Einmalig
./monitor_live.sh

# Oder live (aktualisiert jede Sekunde)
watch -n 1 ./monitor_live.sh
```

### Testing
```bash
# Basic Test
./test.sh

# Heartbeat-Test
./test_heartbeat.sh

# Chaos Engineering (60s)
./chaos_test.py --duration 60
```

### Stoppen
```bash
./stop.sh
```

---

## 🎓 Architektur-Übersicht

### Daemon-Hierarchie

```
start.py
  └─> Daemon-1 (COMMUNICATOR-1) ← Master
       ├─> Daemon-2 (COMMUNICATOR-2)
       ├─> Daemon-3-5 (WATCHDOGS) → Heartbeat Monitor
       └─> Daemon-6-10 (WORKFLOWS) → Send Heartbeats
```

### Heartbeat-Flow

```
Workflows/Comms  ──→ Heartbeat (every 2s)
                 ──→ Unix Socket (UDP)
                 ──→ Watchdogs
                      │
                 Timeout > 6s?
                      │
                 ┌────▼────┐
                 │ FAILURE │
                 └────┬────┘
                      │
              Restart Request
                      │
                      ▼
              Communicator spawns new daemon
```

**Recovery Time:** 8-10 Sekunden

---

## 🐛 Troubleshooting

### Problem: Keine Daemons starten

```bash
# Prüfe ob alte Prozesse laufen
pgrep -f nexus_daemon.py

# Falls ja, cleanup
./stop.sh

# Runtime-Dir cleanen
rm -rf /tmp/nexus

# Neu starten
./start.py
```

### Problem: "Permission denied"

```bash
chmod +x *.py *.sh
```

### Problem: Sockets existieren nicht

```bash
ls -la /tmp/nexus/

# Sollte zeigen:
# control.sock
# heartbeat_1.sock
# heartbeat_2.sock
# heartbeat_3.sock
```

### Problem: Daemons crashen sofort

```bash
# Logs checken (wenn vorhanden)
cat /tmp/nexus/*.log

# Oder manuell starten um Output zu sehen
python3 nexus_daemon.py
```

---

## 📊 Erwartete Output-Beispiele

### Erfolgreicher Start

```
╔════════════════════════════════════════╗
║   AEON NEXUS - System Bootstrap        ║
╚════════════════════════════════════════╝

[BOOTSTRAP] Runtime directory: /tmp/nexus
[BOOTSTRAP] Cleaned old socket: control.sock

🚀 Starting master daemon...

[BOOTSTRAP] Master daemon PID: 12345
[BOOTSTRAP] Daemon will spawn cluster...
```

### Monitor Output

```
📊 Active Daemons: 10

PID    ROLE         ID       UPTIME     CPU%    MEM      STATUS
------ ------------ -------- ---------- ------- -------- ----------
1234   COMM         1        00:03      0.5%    12.3MB   ●
1235   COMM         2        00:03      0.4%    11.8MB   ●
1236   WATCHDOG     1        00:03      0.3%    10.2MB   ●
1237   WATCHDOG     2        00:03      0.3%    10.1MB   ●
1238   WATCHDOG     3        00:03      0.3%    10.0MB   ●
1239   WORKFLOW     1        00:03      2.1%    15.4MB   ●
```

### Chaos Test Output

```
[3.2s] Current daemons: 10
💀 Killed PID 1243 (WORKFLOW) - Total kills: 1
   Watchdogs should detect in ~6.0s
   Restart should happen shortly after

...

═══════════════════════════════════════════════════════════
📊 Chaos Test Results:
   Duration:        60.0s
   Daemons killed:  20
   Final daemons:   10

✅ Cluster survived chaos! Auto-restart working.
```

---

## 📚 Weitere Dokumentation

- **README.md** - Vollständige Feature-Dokumentation
- **QUICKSTART.md** - Schritt-für-Schritt 2-Terminal Setup
- **LOAD_BALANCING.md** - Future Load-Balancing Architektur

---

## 🎯 Features (v1.1)

✅ **Bootstrap & Role Assignment**
- Universal Daemons
- Auto-Spawning
- Dynamic Role Assignment

✅ **Heartbeat System**
- 2s Interval
- 6s Failure Detection
- Auto-Recovery

✅ **Monitoring**
- Live Process Stats
- Socket Status
- Color-Coded Output

✅ **Testing**
- Basic Tests
- Heartbeat Tests
- Chaos Engineering

---

## 🔮 Roadmap (v1.2+)

- [ ] Quorum-based Decisions
- [ ] Task Queue System
- [ ] ChaCha20 Encryption
- [ ] Intra-Node Load Balancing
- [ ] Inter-Node Communication (TCP)
- [ ] Docker Integration

---

## 💡 Support

Bei Fragen oder Problemen:
1. Lies `README.md` für Details
2. Siehe `QUICKSTART.md` für Setup-Guide
3. Prüfe Logs in `/tmp/nexus/`
4. Teste mit `./test_heartbeat.sh`

---

**AEON Nexus v1.1 - Consumer-Grade Daemon Orchestration**
**Built with Python stdlib only - No external dependencies!**

🚀 Happy Testing!
