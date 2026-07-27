# HA Load Balancer — Test Suite

Bash-based test suite for the HA Proxy Load Balancer project. Tests validate configuration parsing, template processing, health check logic, and deployment behavior.

## Structure

```
tests/
├── run_tests.sh              # Test runner (entry point)
├── test_helper.sh            # Shared assertion helpers & test utilities
├── test_entrypoint.sh        # entrypoint.sh — config generation from env vars
├── test_deploy.sh            # deploy.sh — template processing & file deployment
├── test_config.sh            # config.sh — variable defaults & validation
├── test_ha_check.sh          # ha-check-haproxy.sh — health check logic
├── test_install_deps.sh      # install-dependencies.sh — package install logic
├── test_templates.sh         # Templates — structure, variable markers, paths
└── README.md                 # This file
```

## Quick Start

```bash
# Run all tests
cd tests && bash run_tests.sh

# Run a specific test group
cd tests && bash run_tests.sh entrypoint

# Run individual test file
bash tests/test_entrypoint.sh
```

## Test Coverage

| Test File | What It Tests |
|-----------|--------------|
| `test_entrypoint.sh` | BACKENDS_LIST parsing, BACKENDS_FILE priority, ROUTER_ID derivation, INITIAL_STATE logic, keepalived.conf/haproxy.cfg generation, certificate generation, default values, whitespace sanitization |
| `test_deploy.sh` | config.sh/node.conf requirements, backend directive building, keepalived variable substitution, haproxy variable substitution, status messages, directory creation, file permissions, cert generation |
| `test_config.sh` | Default variable values, BACKENDS array structure, IP:PORT format validation, BACKEND_USER default, SMTP comment status, multicast source |
| `test_ha_check.sh` | pgrep logic, socket check, ss fallback, full script behavior, file permissions, shebang, strict mode, syslog logging |
| `test_install_deps.sh` | Package list, sysctl parameters, HAProxy enable, keepalived directory, apt-get update, heredoc format |
| `test_templates.sh` | haproxy.cfg sections, keepalived.conf sections, variable markers, file paths, docker-compose keys, backends.conf format, node.conf variables, Dockerfile structure |

## Assertions Available

| Function | Purpose |
|----------|---------|
| `assert_eq expected actual` | Values must be equal |
| `assert_contains haystack needle` | String must contain substring |
| `assert_not_contains haystack needle` | String must NOT contain substring |
| `assert_file_contains file needle` | File must contain substring |
| `assert_file_exists file` | File must exist |
| `assert_file_not_exists file` | File must NOT exist |
| `assert_gt a b` | a must be greater than b |
| `assert_true condition` | Condition must evaluate to true |
| `assert_exit_code actual expected` | Exit code must match |

## Design Decisions

- **No external dependencies** — tests use only bash built-ins and standard Linux tools
- **Isolated test logic** — each test file sources `test_helper.sh` for assertions but doesn't run actual services (HAProxy/keepalived would block the terminal)
- **Script analysis tests** — for scripts that start long-running processes (entrypoint.sh, deploy.sh), we test the config generation logic inline or analyze script content for expected patterns
- **Real execution tests** — for short-running scripts (ha-check-haproxy.sh), we execute the actual script and verify exit codes

## Adding Tests

1. Create `tests/test_<script>.sh`
2. Source `test_helper.sh` at the top
3. Use `run_test "description" <<'EOF'` blocks for isolated test cases
4. Use assertion helpers (`assert_eq`, `assert_contains`, etc.)
5. Run with `bash run_tests.sh` to verify

## CI Integration

Add to your CI pipeline:

```yaml
- name: Run tests
  run: |
    cd tests
    bash run_tests.sh
```
