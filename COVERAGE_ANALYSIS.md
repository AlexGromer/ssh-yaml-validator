# YAML Validator Coverage Analysis

## Методика расчёта полноты покрытия

### Категории проверок

Полное покрытие YAML валидации включает следующие домены:

| Категория | Вес | Описание |
|-----------|-----|----------|
| **A. YAML Syntax** | 25% | Базовый синтаксис YAML |
| **B. YAML Semantics** | 15% | Семантика и типизация YAML |
| **C. Kubernetes Base** | 20% | Базовые проверки K8s ресурсов |
| **D. Kubernetes Security** | 25% | Безопасность K8s (PSS, RBAC) |
| **E. Kubernetes Best Practices** | 15% | Лучшие практики |

---

## A. YAML Syntax (25%)

### Источник: yamllint rules + YAML spec

| # | Проверка | yamllint | Наш валидатор | Статус |
|---|----------|----------|---------------|--------|
| A1 | BOM detection | - | check_bom | ✅ |
| A2 | Windows encoding (CRLF) | new-lines | check_windows_encoding | ✅ |
| A3 | Tabs vs spaces | indentation | check_tabs | ✅ |
| A4 | Trailing whitespace | trailing-spaces | check_trailing_whitespace | ✅ |
| A5 | Indentation consistency | indentation | check_indentation | ✅ |
| A6 | Empty files | - | check_empty_file | ✅ |
| A7 | Document markers (---/...) | document-start/end | check_document_markers | ✅ |
| A8 | Duplicate keys | key-duplicates | check_duplicate_keys | ✅ |
| A9 | Empty keys | empty-values | check_empty_keys | ✅ |
| A10 | Unpaired quotes | - | check_basic_syntax | ✅ |
| A11 | Unpaired brackets | brackets/braces | check_basic_syntax | ✅ |
| A12 | Colon spacing | colons | check_colons_spacing | ✅ |
| A13 | Comment formatting | comments | check_comment_format | ✅ |
| A14 | Comment indentation | comments-indentation | check_comment_indentation | ✅ |
| A15 | Line length limit | line-length | check_line_length | ✅ |
| A16 | Empty lines control | empty-lines | check_empty_lines | ✅ |
| A17 | Newline at EOF | new-line-at-end-of-file | check_newline_at_eof | ✅ |
| A18 | Key ordering (K8s) | key-ordering | check_key_ordering | ✅ OPT |
| A19 | Multiline blocks (|, >) | - | check_multiline_blocks | ✅ |
| A20 | Flow style ({}, []) | braces/brackets | check_flow_style | ✅ |
| A21 | Brackets spacing | brackets | check_brackets_spacing | ✅ |
| A22 | Truthy values (yamllint) | truthy | check_truthy_values | ✅ |

**Покрытие A: 22/22 = 100%** *(A18 опционально, включается через --key-ordering)*

---

## B. YAML Semantics (15%)

### Источник: YAML 1.1/1.2 spec, parser edge cases

| # | Проверка | Источник | Наш валидатор | Статус |
|---|----------|----------|---------------|--------|
| B1 | Boolean variants (yes/no) | truthy | check_special_values | ✅ |
| B2 | Norway problem (NO→false) | truthy | check_extended_norway | ✅ |
| B3 | Null variants (~, Null) | - | check_null_values | ✅ |
| B4 | Octal numbers (0644) | octal-values | check_numeric_formats | ✅ |
| B5 | Hex numbers (0xFF) | - | check_numeric_formats | ✅ |
| B6 | Sexagesimal (21:00→1260) | - | check_sexagesimal | ✅ |
| B7 | Scientific notation (1e10) | float-values | check_implicit_types | ✅ |
| B8 | Infinity/NaN (.inf/.nan) | float-values | check_implicit_types | ✅ |
| B9 | Timestamps (2024-01-01) | - | check_timestamp_values | ✅ |
| B10 | Version as float (1.0→1) | - | check_version_numbers | ✅ |
| B11 | Anchors (&name) | anchors | check_anchors_aliases | ✅ |
| B12 | Aliases (*name) | anchors | check_anchors_aliases | ✅ |
| B13 | Merge keys (<<:) | - | check_merge_keys | ✅ |
| B14 | YAML bomb detection | - | check_yaml_bomb | ✅ |
| B15 | String quoting requirements | quoted-strings | check_string_quoting | ✅ |
| B16 | Embedded JSON validation | - | check_embedded_json | ✅ |
| B17 | Float numeral before decimal | float-values | check_float_leading_zero | ✅ |
| B18 | Forbid NaN/Inf explicitly | float-values | check_special_floats | ✅ |
| B19 | Max nesting depth | - | check_nesting_depth | ✅ |
| B20 | Unicode normalization | - | check_unicode_normalization | ✅ |

**Покрытие B: 20/20 = 100%**

---

## C. Kubernetes Base (20%)

### Источник: K8s API spec, kubeconform

| # | Проверка | Источник | Наш валидатор | Статус |
|---|----------|----------|---------------|--------|
| C1 | apiVersion required | K8s spec | check_kubernetes_specific | ✅ |
| C2 | kind required | K8s spec | check_kubernetes_specific | ✅ |
| C3 | metadata required | K8s spec | check_kubernetes_specific | ✅ |
| C4 | metadata.name required | K8s spec | check_kubernetes_specific | ✅ |
| C5 | spec required (for workloads) | K8s spec | check_kubernetes_specific | ✅ |
| C6 | Label format (RFC 1123) | K8s spec | check_label_format | ✅ |
| C7 | Annotation length ≤256KB | K8s spec | check_annotation_length | ✅ |
| C8 | DNS-compatible names | K8s spec | check_dns_names | ✅ |
| C9 | Container name format | K8s spec | check_container_name | ✅ |
| C10 | Resource quantities format | K8s spec | check_resource_quantities | ✅ |
| C11 | Port ranges (1-65535) | K8s spec | check_port_ranges | ✅ |
| C12 | Protocol values | K8s spec | check_network_values | ✅ |
| C13 | IP/CIDR format | K8s spec | check_network_values | ✅ |
| C14 | Deprecated API versions | K8s spec | check_deprecated_api | ✅ |
| C15 | Selector/template match | K8s spec | check_selector_match | ✅ |
| C16 | Service→Pod selector | kube-linter | check_service_selector | ✅ |
| C17 | ConfigMap key validation | K8s spec | check_configmap_keys | ✅ |
| C18 | Ingress rules validation | K8s spec | check_ingress_rules | ✅ |
| C19 | CronJob schedule format | K8s spec | check_cronjob_schedule | ✅ |
| C20 | HPA min/max validation | K8s spec | check_hpa_config | ✅ |
| C21 | PDB configuration | K8s spec | check_pdb_config | ✅ |
| C22 | Secret base64 validation | K8s spec | check_base64_in_secrets | ✅ |
| C23 | ENV var validation | K8s spec | check_env_vars | ✅ |
| C24 | replicas type (integer) | K8s spec | check_replicas_type | ✅ |
| C25 | imagePullPolicy values | K8s spec | check_image_pull_policy | ✅ |
| C26 | restartPolicy values | K8s spec | check_restart_policy | ✅ |
| C27 | serviceType values | K8s spec | check_service_type | ✅ |
| C28 | Probe configuration | K8s spec | check_probe_config | ✅ |
| C29 | Field name typos (snake→camel) | - | check_kubernetes_specific | ✅ |
| C30 | Schema validation (full) | kubeconform | - | ❌ COMPLEX |
| **Partial Schema (Bash)** ||||
| C31 | Field types (integer/string) | K8s spec | check_field_types | ✅ OPT |
| C32 | Enum value validation | K8s spec | check_enum_values | ✅ OPT |
| C33 | Required nested fields | K8s spec | check_required_nested | ✅ OPT |

**Покрытие C: 32/33 = 97%** *(C30 требует внешних зависимостей; C31-C33 частичная реализация через --partial-schema)*

---

## D. Kubernetes Security (25%)

### Источник: Pod Security Standards, kube-linter, CIS Benchmarks

| # | Проверка | PSS Level | Наш валидатор | Статус |
|---|----------|-----------|---------------|--------|
| **PSS Baseline** ||||
| D1 | hostNetwork: false | Baseline | check_security_best_practices | ✅ |
| D2 | hostPID: false | Baseline | check_security_best_practices | ✅ |
| D3 | hostIPC: false | Baseline | check_security_best_practices | ✅ |
| D4 | privileged: false | Baseline | check_security_best_practices | ✅ |
| D5 | hostPath volumes | Baseline | check_security_best_practices | ✅ |
| D6 | hostPort restriction | Baseline | check_pss_baseline | ✅ |
| D7 | Capabilities restrictions | Baseline | check_pss_baseline | ✅ |
| D8 | procMount: Default | Baseline | check_pss_baseline | ✅ |
| D9 | Seccomp profile | Baseline | check_pss_restricted | ✅ |
| D10 | Sysctls whitelist | Baseline | check_pss_baseline | ✅ |
| D11 | AppArmor profile | Baseline | check_pss_baseline | ✅ |
| D12 | SELinux options | Baseline | check_pss_baseline | ✅ |
| **PSS Restricted** ||||
| D13 | allowPrivilegeEscalation: false | Restricted | check_security_context | ✅ |
| D14 | runAsNonRoot: true | Restricted | check_security_context | ✅ |
| D15 | runAsUser ≠ 0 | Restricted | check_pss_restricted | ✅ |
| D16 | Volume type whitelist | Restricted | check_pss_restricted | ✅ |
| D17 | Seccomp required | Restricted | check_pss_restricted | ✅ |
| **kube-linter Security** ||||
| D18 | docker.sock mount | kube-linter | check_sensitive_mounts | ✅ |
| D19 | Sensitive host mounts | kube-linter | check_sensitive_mounts | ✅ |
| D20 | Writable host mount | kube-linter | check_writable_hostpath | ✅ |
| D21 | SSH port (22) detection | kube-linter | check_privileged_ports | ✅ |
| D22 | Privileged ports (<1024) | kube-linter | check_privileged_ports | ✅ |
| D23 | drop NET_RAW capability | kube-linter | check_drop_net_raw | ✅ |
| D24 | readOnlyRootFilesystem | kube-linter | check_security_context | ✅ |
| D25 | CVE-2023-3676 (subPath) | CVE | check_volume_mounts | ✅ |
| **CIS/RBAC** ||||
| D26 | Secrets in env vars | kube-linter | check_secrets_in_env | ✅ |
| D27 | Default service account | kube-linter | check_default_service_account | ✅ |
| D28 | cluster-admin binding | kube-linter | check_rbac_security | ✅ |
| D29 | Wildcard in RBAC rules | kube-linter | check_rbac_security | ✅ |
| D30 | Access to secrets check | kube-linter | check_rbac_security | ✅ |

**Покрытие D: 30/30 = 100%**

---

## E. Kubernetes Best Practices (15%)

### Источник: Polaris, kube-linter

| # | Проверка | Источник | Наш валидатор | Статус |
|---|----------|----------|---------------|--------|
| E1 | Image :latest tag warning | Polaris | check_image_tags | ✅ |
| E2 | Missing liveness probe | Polaris | check_probe_config | ✅ |
| E3 | Missing readiness probe | Polaris | check_probe_config | ✅ |
| E4 | Missing CPU requests | Polaris | check_resource_format | ✅ |
| E5 | Missing CPU limits | Polaris | check_resource_format | ✅ |
| E6 | Missing memory requests | Polaris | check_resource_format | ✅ |
| E7 | Missing memory limits | Polaris | check_resource_format | ✅ |
| E8 | Replicas < 3 (HA) | kube-linter | check_replicas_ha | ✅ |
| E9 | Missing anti-affinity | kube-linter | check_anti_affinity | ✅ |
| E10 | No rolling update strategy | kube-linter | check_rolling_update | ✅ |
| E11 | Dangling services | kube-linter | check_dangling_resources | ✅ |
| E12 | Dangling ingress | kube-linter | check_dangling_resources | ✅ |
| E13 | Dangling HPA | kube-linter | check_dangling_resources | ✅ |
| E14 | Dangling NetworkPolicy | kube-linter | check_dangling_resources | ✅ |
| E15 | Duplicate env vars | kube-linter | check_duplicate_env | ✅ |
| E16 | Missing namespace | kube-linter | check_missing_namespace | ✅ |
| E17 | Priority class not set | kube-linter | check_priority_class | ✅ |
| E18 | Probe ports validation | kube-linter | check_probe_ports | ✅ |
| E19 | Missing owner label | kube-linter | check_owner_label | ✅ |
| E20 | Deckhouse CRD validation | Deckhouse | check_deckhouse_crd | ✅ |

**Покрытие E: 20/20 = 100%**

---

## Итоговое покрытие

| Категория | Вес | Покрытие | Взвешенное |
|-----------|-----|----------|------------|
| A. YAML Syntax | 25% | 100% | 25.0% |
| B. YAML Semantics | 15% | 100% | 15.0% |
| C. Kubernetes Base | 20% | 97% | 19.4% |
| D. Kubernetes Security | 25% | 100% | 25.0% |
| E. Kubernetes Best Practices | 15% | 100% | 15.0% |

**ОБЩЕЕ ПОКРЫТИЕ: 99.4%** *(+11.25% vs v2.7.0)*

---

## История изменений покрытия

| Версия | Покрытие | Дельта | Основные изменения |
|--------|----------|--------|-------------------|
| v2.5.0 | 63.2% | - | Базовая версия анализа |
| v2.6.0 | 82.2% | +19.0% | PSS Baseline/Restricted, RBAC, yamllint-compatible |
| v2.7.0 | 88.15% | +5.95% | Severity levels, A14, B17-B20, D20, D23 |
| v2.8.0 | 99.4% | +11.25% | A18, C31-C33, E8-E19, auto-fixer v3.0.0 |

---

## Реализованные проверки в v2.8.0

### A18: K8s Key Ordering (опционально)
- `check_key_ordering` — проверка порядка ключей по конвенции K8s
- Порядок: apiVersion → kind → metadata → spec → data → status
- Включается через `--key-ordering` или `--all-checks`

### C31-C33: Partial Schema Validation (опционально)
- `check_field_types` — проверка типов полей (replicas, ports = integer)
- `check_enum_values` — проверка enum значений (restartPolicy, imagePullPolicy, protocol, type)
- `check_required_nested` — проверка обязательных вложенных полей
- Включается через `--partial-schema` или `--all-checks`

### E8-E19: Best Practices (12 новых функций)
- `check_replicas_ha` — предупреждение при replicas < 3
- `check_anti_affinity` — отсутствие podAntiAffinity в Deployment
- `check_rolling_update` — отсутствие/неверная стратегия обновления
- `check_dangling_resources` — эвристика для висячих Service/Ingress/HPA/NetworkPolicy
- `check_duplicate_env` — дублирующиеся имена env переменных
- `check_missing_namespace` — отсутствие namespace в namespaced ресурсах
- `check_priority_class` — отсутствие priorityClassName
- `check_probe_ports` — несоответствие портов в probes и containerPort
- `check_owner_label` — отсутствие app.kubernetes.io/managed-by или owner label

### Auto-Fixer v3.0.0 (13 безопасных + 5 интерактивных)

**Автоматические исправления:**
1. BOM removal
2. CRLF → LF
3. Tabs → Spaces
4. Trailing whitespace
5. Boolean case (True → true)
6. List spacing (-item → - item)
7. Document markers (---- → ---)
8. Colon spacing (key:value → key: value)
9. Empty lines (>2 → 2)
10. Newline at EOF
11. Bracket spacing ([a,b] → [a, b])
12. Comment space (#comment → # comment)
13. Truthy values (yes/no → true/false)

**Интерактивные исправления (-i):**
- Security: privileged, hostNetwork, hostPID, hostIPC, allowPrivilegeEscalation, runAsUser: 0
- Image tags: :latest → :stable
- Missing namespace: добавление с запросом имени
- Missing probes: показ шаблона
- Missing resources: показ шаблона

---

## Оставшиеся улучшения

### Единственное неимплементированное
1. **C30: Full JSON Schema validation** — требует внешних зависимостей (kubeconform, ~50MB схем)
   - Рекомендация: использовать вместе с kubeconform для полной валидации
   - Частичная реализация через C31-C33

### Расширения (отдельные модули)
См. ROADMAP.md для списка YAML-систем:
- Ansible, Helm, GitLab CI, GitHub Actions, Docker Compose, ArgoCD, Tekton и др.

---

## Новые опции командной строки v2.8.0

```bash
# Опциональные проверки
--key-ordering         # Включить A18: проверку порядка ключей K8s
--partial-schema       # Включить C31-C33: частичную схема-валидацию
--all-checks           # Включить все опциональные проверки

# Режимы строгости (из v2.7.0)
-s, --strict           # WARNING/SECURITY = ERROR
--security-mode MODE   # strict|normal|permissive
```

---

## Источники

- [yamllint Rules](https://yamllint.readthedocs.io/en/stable/rules.html)
- [kube-linter Checks](https://github.com/stackrox/kube-linter/blob/main/docs/generated/checks.md)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Polaris](https://github.com/FairwindsOps/polaris)
- [YAML 1.2 Spec](https://yaml.org/spec/1.2.2/)
- [The YAML Document from Hell](https://ruudvanasseldonk.com/2023/01/11/the-yaml-document-from-hell)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
