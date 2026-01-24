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
| A14 | Comment indentation | comments-indentation | - | ❌ TODO |
| A15 | Line length limit | line-length | check_line_length | ✅ |
| A16 | Empty lines control | empty-lines | check_empty_lines | ✅ |
| A17 | Newline at EOF | new-line-at-end-of-file | check_newline_at_eof | ✅ |
| A18 | Key ordering | key-ordering | - | ❌ OPTIONAL |
| A19 | Multiline blocks (|, >) | - | check_multiline_blocks | ✅ |
| A20 | Flow style ({}, []) | braces/brackets | check_flow_style | ✅ |
| A21 | Brackets spacing | brackets | check_brackets_spacing | ✅ |
| A22 | Truthy values (yamllint) | truthy | check_truthy_values | ✅ |

**Покрытие A: 19/22 = 86%**

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
| B17 | Float numeral before decimal | float-values | - | ❌ TODO |
| B18 | Forbid NaN/Inf explicitly | float-values | - | ⚠️ PARTIAL |
| B19 | Max nesting depth | - | - | ❌ TODO |
| B20 | Unicode normalization | - | - | ❌ TODO |

**Покрытие B: 16/20 = 80%**

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

**Покрытие C: 29/30 = 97%**

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
| D20 | Writable host mount | kube-linter | - | ❌ TODO |
| D21 | SSH port (22) detection | kube-linter | check_privileged_ports | ✅ |
| D22 | Privileged ports (<1024) | kube-linter | check_privileged_ports | ✅ |
| D23 | drop NET_RAW capability | kube-linter | - | ❌ TODO |
| D24 | readOnlyRootFilesystem | kube-linter | check_security_context | ✅ |
| D25 | CVE-2023-3676 (subPath) | CVE | check_volume_mounts | ✅ |
| **CIS/RBAC** ||||
| D26 | Secrets in env vars | kube-linter | check_secrets_in_env | ✅ |
| D27 | Default service account | kube-linter | check_default_service_account | ✅ |
| D28 | cluster-admin binding | kube-linter | check_rbac_security | ✅ |
| D29 | Wildcard in RBAC rules | kube-linter | check_rbac_security | ✅ |
| D30 | Access to secrets check | kube-linter | check_rbac_security | ✅ |

**Покрытие D: 28/30 = 93%**

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
| E8 | Replicas < 3 (HA) | kube-linter | - | ❌ TODO |
| E9 | Missing anti-affinity | kube-linter | - | ❌ TODO |
| E10 | No rolling update strategy | kube-linter | - | ❌ TODO |
| E11 | Dangling services | kube-linter | - | ❌ TODO |
| E12 | Dangling ingress | kube-linter | - | ❌ TODO |
| E13 | Dangling HPA | kube-linter | - | ❌ TODO |
| E14 | Dangling NetworkPolicy | kube-linter | - | ❌ TODO |
| E15 | Duplicate env vars | kube-linter | - | ❌ TODO |
| E16 | Missing namespace | kube-linter | - | ❌ TODO |
| E17 | Priority class not set | kube-linter | - | ❌ TODO |
| E18 | Probe ports validation | kube-linter | - | ❌ TODO |
| E19 | Missing owner label | kube-linter | - | ❌ TODO |
| E20 | Deckhouse CRD validation | Deckhouse | check_deckhouse_crd | ✅ |

**Покрытие E: 8/20 = 40%**

---

## Итоговое покрытие

| Категория | Вес | Покрытие | Взвешенное |
|-----------|-----|----------|------------|
| A. YAML Syntax | 25% | 86% | 21.5% |
| B. YAML Semantics | 15% | 80% | 12.0% |
| C. Kubernetes Base | 20% | 97% | 19.4% |
| D. Kubernetes Security | 25% | 93% | 23.3% |
| E. Kubernetes Best Practices | 15% | 40% | 6.0% |

**ОБЩЕЕ ПОКРЫТИЕ: 82.2%** *(+19% vs v2.5.0)*

---

## История изменений покрытия

| Версия | Покрытие | Дельта | Основные изменения |
|--------|----------|--------|-------------------|
| v2.5.0 | 63.2% | - | Базовая версия анализа |
| v2.6.0 | 82.2% | +19.0% | PSS Baseline/Restricted, RBAC, yamllint-compatible |

---

## Реализованные проверки в v2.6.0

### PSS Security (8 новых функций)
- `check_pss_baseline` — hostPort, capabilities, procMount, sysctls, AppArmor, SELinux
- `check_pss_restricted` — runAsUser/Group, fsGroup, volume types, seccomp
- `check_sensitive_mounts` — docker.sock, /etc, /, /proc, /sys, /dev, kubelet, etcd
- `check_privileged_ports` — SSH (22), Docker API (2375), Kubernetes ports
- `check_rbac_security` — cluster-admin, wildcards, default SA, secrets access
- `check_secrets_in_env` — PASSWORD, TOKEN, API_KEY patterns in env
- `check_default_service_account` — serviceAccountName: default warning

### yamllint-compatible (7 новых функций)
- `check_line_length` — предупреждение о строках > 120 символов
- `check_comment_format` — пробел после # в комментариях
- `check_empty_lines` — не более 2 пустых строк подряд
- `check_newline_at_eof` — POSIX-совместимость
- `check_colons_spacing` — пробелы у двоеточий
- `check_brackets_spacing` — пробелы в скобках
- `check_truthy_values` — yes/no/on/off предупреждения

---

## Оставшиеся улучшения

### Высокий приоритет
1. **D20: Writable host mount** — проверка readOnly: false в hostPath
2. **D23: drop NET_RAW capability** — best practice для сетевой безопасности

### Средний приоритет
3. **A14: Comment indentation** — yamllint comments-indentation rule
4. **B17-B20** — дополнительные семантические проверки

### Низкий приоритет (Best Practices)
5. **E8-E19** — HA, dangling resources, namespaces, priority classes

---

## Источники

- [yamllint Rules](https://yamllint.readthedocs.io/en/stable/rules.html)
- [kube-linter Checks](https://github.com/stackrox/kube-linter/blob/main/docs/generated/checks.md)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Polaris](https://github.com/FairwindsOps/polaris)
- [YAML 1.2 Spec](https://yaml.org/spec/1.2.2/)
- [The YAML Document from Hell](https://ruudvanasseldonk.com/2023/01/11/the-yaml-document-from-hell)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
