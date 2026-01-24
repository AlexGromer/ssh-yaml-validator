# YAML Validator Roadmap

## Current Status: v2.7.0

**Coverage: 87.7%** (estimated after v2.7.0 additions)

---

## Implemented Features (v2.7.0)

### Severity Levels System
- **ERROR** - Blocks deployment, always fails validation
- **WARNING** - Should be fixed, fails in `--strict` mode
- **INFO** - Style/informational, never fails
- **SECURITY** - Security issues, behavior depends on `--security-mode`:
  - `strict` - SECURITY = ERROR (production)
  - `normal` - SECURITY = WARNING (default)
  - `permissive` - SECURITY = INFO (test/dev)

### Command Line Options
```bash
yaml_validator.sh [OPTIONS] <file_or_directory>

# Severity control
-s, --strict                    # Strict mode: WARNING/SECURITY = ERROR
--security-mode strict          # Production: security = error
--security-mode normal          # Default: security = warning
--security-mode permissive      # Test/dev: security = info
```

---

## C30: Full JSON Schema Validation

### What it requires

JSON Schema validation for Kubernetes manifests would require:

1. **Schema Files (~50MB)**
   - Official Kubernetes OpenAPI schemas from `kubernetes/kubernetes` repo
   - Per-version schemas (1.25, 1.26, 1.27, 1.28, 1.29, 1.30)
   - CRD schemas for Deckhouse, Istio, etc.

2. **Schema Parser**
   - Pure Bash JSON/YAML parser (extremely complex)
   - OR external dependency (Python `jsonschema`, `kubeconform`)

3. **Validation Logic**
   - Type checking (string, integer, boolean, array, object)
   - Required fields validation
   - Enum value validation
   - Pattern matching (regex)
   - Nested object traversal

### Why not implemented

| Reason | Impact |
|--------|--------|
| Air-gapped environment | Cannot fetch schemas dynamically |
| Schema size (~50MB) | Impractical for embedded |
| Parser complexity | Would require 5000+ lines of Bash |
| Maintenance burden | New K8s version = new schemas |

### Alternatives

1. **kubeconform** - Standalone Go binary, works offline
2. **kubeval** - Similar, but deprecated
3. **pluto** - Deprecated API detection (already implemented)

### Recommendation

For full schema validation in air-gapped environments:

```bash
# Download kubeconform binary once
curl -LO https://github.com/yannh/kubeconform/releases/download/v0.6.4/kubeconform-linux-amd64.tar.gz
tar xzf kubeconform-linux-amd64.tar.gz

# Use alongside yaml_validator.sh
./yaml_validator.sh manifests/           # Our checks
./kubeconform -summary manifests/        # Schema validation
```

---

## Future YAML Implementations Roadmap

### Priority 1: High Demand

| System | Description | Effort | Status |
|--------|-------------|--------|--------|
| **Ansible** | Playbooks, roles, inventory | High | Planned |
| **Helm** | Chart.yaml, values.yaml | Medium | Planned |
| **GitLab CI** | .gitlab-ci.yml | Medium | Planned |
| **GitHub Actions** | .github/workflows/*.yml | Medium | Planned |

### Priority 2: Container/Cloud

| System | Description | Effort | Status |
|--------|-------------|--------|--------|
| **Docker Compose** | docker-compose.yml | Low | Planned |
| **Podman Compose** | Similar to Docker Compose | Low | Planned |
| **Terraform** | terraform.tfvars, *.tf.json | Medium | Considered |
| **CloudFormation** | AWS templates | Medium | Considered |

### Priority 3: Kubernetes Ecosystem

| System | Description | Effort | Status |
|--------|-------------|--------|--------|
| **ArgoCD** | Application, AppProject CRDs | Low | Planned |
| **Tekton** | Pipeline, Task CRDs | Low | Planned |
| **Kustomize** | kustomization.yaml | Low | Planned |
| **Crossplane** | XRD, Composition | Medium | Considered |
| **Flux** | GitOps CRDs | Low | Considered |

### Priority 4: Monitoring/Service Mesh

| System | Description | Effort | Status |
|--------|-------------|--------|--------|
| **Prometheus** | ServiceMonitor, PrometheusRule | Low | Considered |
| **Istio** | VirtualService, Gateway, etc. | Medium | Considered |
| **Linkerd** | ServiceProfile | Low | Considered |
| **Cilium** | CiliumNetworkPolicy | Low | Considered |

### Priority 5: Other YAML Systems

| System | Description | Effort | Status |
|--------|-------------|--------|--------|
| **OpenAPI/Swagger** | API specifications | High | Future |
| **Azure Pipelines** | azure-pipelines.yml | Medium | Future |
| **CircleCI** | .circleci/config.yml | Low | Future |
| **Travis CI** | .travis.yml | Low | Future |
| **Concourse CI** | pipeline.yml | Medium | Future |
| **Salt** | State files | High | Future |
| **Puppet Hiera** | data/*.yaml | Medium | Future |
| **Spring Boot** | application.yml | Low | Future |

---

## Implementation Notes per System

### Ansible
```yaml
# Key checks:
- hosts: validation (inventory reference)
- tasks: structure (name, module, args)
- vars: type checking
- roles: dependencies
- become: security implications
- delegate_to: patterns
- Jinja2 templates: {{ var }} syntax
```

### Helm
```yaml
# Key checks:
- Chart.yaml: required fields (apiVersion, name, version)
- values.yaml: type consistency
- templates/*.yaml: Go template syntax {{ .Values.x }}
- _helpers.tpl: define/include patterns
- NOTES.txt: template rendering
```

### GitLab CI
```yaml
# Key checks:
- stages: order and references
- jobs: required keys (script, stage)
- rules/only/except: syntax
- variables: expansion
- extends: inheritance
- artifacts/cache: paths
- needs: DAG validation
```

### GitHub Actions
```yaml
# Key checks:
- on: trigger validation
- jobs: required keys
- steps: run/uses validation
- env: variable format
- secrets: reference validation
- matrix: expansion
- needs: job dependency graph
```

### Docker Compose
```yaml
# Key checks:
- version: compatibility
- services: required keys (image or build)
- ports: format (host:container)
- volumes: mount syntax
- networks: references
- depends_on: circular detection
- environment: format
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v2.7.0 | 2026-01-24 | Severity levels, A14, B17-B20, D20, D23 |
| v2.6.0 | 2026-01-24 | PSS Baseline/Restricted, RBAC, yamllint |
| v2.5.0 | 2026-01-23 | 7 new check functions |
| v2.0.0 | 2026-01-22 | Major rewrite |
| v1.0.0 | 2026-01-21 | Initial release |

---

## Contributing

To add support for a new YAML system:

1. Create `check_<system>_*` functions in yaml_validator.sh
2. Add calls in `validate_yaml_file()`
3. Create test files in `test_samples/`
4. Update COVERAGE_ANALYSIS.md
5. Update this ROADMAP.md

### Function naming convention
```bash
check_<system>_<category>()
# Examples:
check_ansible_playbook_structure()
check_helm_chart_yaml()
check_gitlab_ci_stages()
check_github_actions_workflow()
```
