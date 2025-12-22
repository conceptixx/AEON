# AEON Orchestrator v1.3.0 - RTM & Test Plan

## Release Summary

**Version:** 1.3.0  
**Release Date:** 2025-01-15  
**Type:** Minor Feature Release  
**Breaking Changes:** None (backward compatible)

## Key Changes

### Dynamic CLI Flag Parsing (Protocol-Oriented Design)

The orchestrator now reads ALL CLI flag definitions from the manifest's `cli.flags_schema`, making it a pure execution engine with zero hardcoded business logic. This enables:

- **Self-describing interfaces**: The manifest IS the API contract
- **Zero-code updates**: Modify CLI behavior by editing JSON only
- **Type-safe validation**: Schema enforces types, requirements, defaults
- **Unknown flag policies**: Configurable warn/error/ignore behavior

### Architecture Pattern: "Protocol-Oriented CLI"

```
Traditional:                   v1.3.0 Protocol-Oriented:
┌─────────────┐               ┌─────────────┐
│ Orchestrator│               │ Orchestrator│ (pure engine)
│   - hardcoded flags         │   - reads schema
│   - business logic          │   - validates dynamically
│   - coupled to use cases    │   - zero business logic
└─────────────┘               └─────────────┘
                                      ↓
                              ┌─────────────┐
                              │  Manifest   │ (protocol spec)
                              │   - defines flags
                              │   - validation rules
                              │   - behavior policy
                              └─────────────┘
```

### Technical Implementation

1. **Bootstrap Parser**: Extracts only `--file:` and `--config:` args
2. **Schema Parser**: Dynamically builds flag parser from manifest JSON
3. **Type System**: Supports bool, string, int, float with conversion
4. **Alias Resolution**: Short flags (-n) and long flags (--noninteractive)
5. **Combined Flags**: Expands -nw → -n -w automatically
6. **Policy Engine**: Configurable unknown flag handling

## Exit Code Contract

| Code | Meaning | When Triggered |
|------|---------|----------------|
| 0 | Success | All actions completed successfully |
| 1 | Runtime Failure | Action execution failed during orchestration |
| 2 | CLI Usage Error | Invalid flags per schema, missing required flags, unknown flags with error policy |
| 3 | Validation Failure | Missing required_now files, schema validation errors |
| 4 | Dependency Failure | Import errors, missing Python modules |

## Backward Compatibility

✅ **Fully backward compatible** with v1.2.x manifests:
- Manifests without `cli.flags_schema` use empty schema (no flags allowed except bootstrap)
- Existing exit codes unchanged
- AEON_ROOT detection unchanged
- Path validation unchanged

## Installation

```bash
# Replace existing orchestrator
cp orchestrator.json.v1.3.py library/orchestrator/orchestrator.json.py
chmod +x library/orchestrator/orchestrator.json.py

# Update manifest to use new schema
cp manifest.install.json manifest/manifest.install.json
```

---

## Manual Test Plan

### Test Environment Setup

```bash
# Set AEON_ROOT for testing (adjust to your system)
export AEON_ROOT=/opt/aeon  # or /usr/local/aeon on macOS

# Create test structure
mkdir -p $AEON_ROOT/library/orchestrator
mkdir -p $AEON_ROOT/manifest
mkdir -p $AEON_ROOT/logs

# Copy files
cp orchestrator.json.v1.3.py $AEON_ROOT/library/orchestrator/
cp manifest.install.json $AEON_ROOT/manifest/
```

### Test Cases

#### TC1: Missing Required Bootstrap Arg (Exit 2)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py
# Expected: Usage message printed to stderr
# Expected Exit Code: 2
echo "Exit: $?"
```

**Expected Output:**
```
AEON Orchestrator v1.3.0 - Dynamic CLI Execution Engine

Usage:
  orchestrator.json.py --file:/path/to/manifest.json [OPTIONS]
...
Exit: 2
```

---

#### TC2: Valid Bootstrap with No Extra Flags (Exit 0)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json
# Expected: Successful execution with summary
# Expected Exit Code: 0
echo "Exit: $?"
```

**Expected Output:**
```
AEON Orchestrator v1.3.0
Root: /opt/aeon
Entry: manifest.install.json
Flags: {
  "enable-cli": false,
  "enable-web": false,
  "noninteractive": false,
  "install-path": null,
  "log-level": "info"
}

Executing 4 actions...
  [1/4] validate_system
  [2/4] install_docker
  [3/4] setup_web_interface
  [4/4] finalize_installation
Exit: 0
```

---

#### TC3: Schema-Defined Boolean Flags (Exit 0)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json \
  -c -w -n
# Expected: Flags parsed and set to true
# Expected Exit Code: 0
echo "Exit: $?"
```

**Expected Output:**
```
AEON Orchestrator v1.3.0
Root: /opt/aeon
Entry: manifest.install.json
Flags: {
  "enable-cli": true,
  "enable-web": true,
  "noninteractive": true,
  "install-path": null,
  "log-level": "info"
}

Executing 4 actions...
  [1/4] validate_system
  [2/4] install_docker
  [3/4] setup_web_interface
  [4/4] finalize_installation
Exit: 0
```

---

#### TC4: Combined Short Flags (Exit 0)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json \
  -cwn
# Expected: Same as TC3 (combined flags expanded)
# Expected Exit Code: 0
echo "Exit: $?"
```

**Expected Output:** Same as TC3

---

#### TC5: Long Flag Names (Exit 0)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json \
  --enable-cli --enable-web --noninteractive
# Expected: Same as TC3
# Expected Exit Code: 0
echo "Exit: $?"
```

**Expected Output:** Same as TC3

---

#### TC6: Value Flags with = Syntax (Exit 0)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json \
  --log-level=debug \
  --install-path=/custom/path
# Expected: String values parsed correctly
# Expected Exit Code: 0
echo "Exit: $?"
```

**Expected Output:**
```
Flags: {
  "enable-cli": false,
  "enable-web": false,
  "noninteractive": false,
  "install-path": "/custom/path",
  "log-level": "debug"
}
Exit: 0
```

---

#### TC7: Value Flags with Space Syntax (Exit 0)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json \
  --log-level debug \
  -p /custom/path
# Expected: Same as TC6
# Expected Exit Code: 0
echo "Exit: $?"
```

**Expected Output:** Same as TC6

---

#### TC8: Unknown Flag with Warn Policy (Exit 0 + Warning)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json \
  --unknown-flag \
  -x
# Expected: Warning printed, but execution continues
# Expected Exit Code: 0
echo "Exit: $?"
```

**Expected Output:**
```
WARNING: Unknown flags ignored: --unknown-flag, -x
AEON Orchestrator v1.3.0
...
Exit: 0
```

---

#### TC9: Missing Required File (Exit 3)

```bash
cd $AEON_ROOT
# Create manifest with missing required_now file
cat > /tmp/test_missing.json <<EOF
{
  "manifest_version": "1.3.0",
  "cli": {"flags_schema": {"flags": []}},
  "required_now": ["nonexistent/file.txt"],
  "actions": []
}
EOF

python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:/tmp/test_missing.json
# Expected: Validation error
# Expected Exit Code: 3
echo "Exit: $?"
```

**Expected Output:**
```
ERROR: Required path does not exist: /opt/aeon/nonexistent/file.txt
Exit: 3
```

---

#### TC10: Noninteractive Mode (No Output, Exit 0)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json \
  -n > /tmp/output.txt 2>&1
# Expected: Minimal output
# Expected Exit Code: 0
cat /tmp/output.txt
echo "Exit: $?"
```

**Expected:** Minimal or no stdout (noninteractive suppresses info)

---

#### TC11: Multiple Config Files (Exit 0)

```bash
cd $AEON_ROOT
# Create test configs
echo '{"test": 1}' > /tmp/config1.json
echo '{"test": 2}' > /tmp/config2.json

python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:manifest/manifest.install.json \
  --config:/tmp/config1.json \
  --config:/tmp/config2.json
# Expected: Multiple configs loaded
# Expected Exit Code: 0
echo "Exit: $?"
```

---

#### TC12: Path Traversal Prevention (Exit 3)

```bash
cd $AEON_ROOT
python3 library/orchestrator/orchestrator.json.v1.3.py \
  --file:../../../etc/passwd
# Expected: Security error
# Expected Exit Code: 3
echo "Exit: $?"
```

**Expected Output:**
```
ERROR: Path traversal detected: ../../../etc/passwd escapes AEON_ROOT
Exit: 3
```

---

### Test Matrix Summary

| TC | Test Scenario | Expected Exit | Key Validation |
|----|---------------|---------------|----------------|
| 1 | No args | 2 | Usage printed |
| 2 | Minimal valid | 0 | Defaults applied |
| 3 | Short flags | 0 | Boolean parsing |
| 4 | Combined flags | 0 | Flag expansion |
| 5 | Long flags | 0 | Alias resolution |
| 6 | Value with = | 0 | String parsing |
| 7 | Value with space | 0 | Multi-arg values |
| 8 | Unknown flags | 0 + warn | Policy enforcement |
| 9 | Missing file | 3 | Validation |
| 10 | Noninteractive | 0 | Output suppression |
| 11 | Multiple configs | 0 | Config loading |
| 12 | Path traversal | 3 | Security |

---

## Acceptance Criteria

✅ All test cases pass with expected exit codes  
✅ No regression in v1.2.x manifest compatibility  
✅ Schema validation catches all error cases  
✅ Unknown flag policy correctly enforced  
✅ Path traversal prevention working  
✅ Noninteractive mode suppresses output  
✅ Combined short flags expand correctly  
✅ Type conversion works for all supported types

---

## Known Limitations

1. **No JSON Schema Validation**: The flags_schema structure is validated structurally but not against a formal JSON Schema
2. **No Multi-Value Flags**: Flags like `--tag tag1 --tag tag2` not supported yet
3. **No Conditional Schemas**: Cannot modify available flags based on runtime conditions
4. **No Auto-Generated Help**: No `--help` flag auto-generation from schema (future enhancement)

## Future Enhancements (v1.4.0+)

- [ ] Auto-generate `--help` from schema
- [ ] Multi-value flag support (arrays)
- [ ] Conditional flag schemas (depends_on)
- [ ] Flag groups and mutual exclusivity
- [ ] JSON Schema validation for manifest
- [ ] Shell completion generation from schema

---

## Coding Surprise 🎁

The **Protocol-Oriented CLI Design** pattern implemented here is inspired by OpenAPI/Swagger for REST APIs, but applied to command-line interfaces. Just as OpenAPI made REST APIs self-describing and automatically generated client SDKs, this pattern makes CLI tools self-describing and enables automatic flag parsing, validation, and eventually help text generation.

**The Big Idea**: Your CLI interface IS your data structure. The manifest becomes a machine-readable contract that both humans and machines can understand. This enables:

1. **Composition**: Manifests can inherit/merge flags from other manifests
2. **Introspection**: Tools can query what flags are available programmatically
3. **Code Generation**: Future work could auto-generate shell completions, docs, etc.
4. **Versioning**: Schema_version tracks CLI interface changes over time

This is similar to how gRPC uses Protocol Buffers, or how GraphQL schemas define available queries. The CLI becomes a **first-class protocol** instead of an afterthought!

---

**END OF RTM**
