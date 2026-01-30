# Phase 1C: Complete Function Optimization Plan

**Цель:** Оптимизировать оставшиеся 73/100 функций до 100% покрытия

**Текущее состояние:** 27/100 (27%) ✅
**Target:** 100/100 (100%)

---

## Оставшиеся Функции (73)

### Kubernetes-Specific Checks (40 функций)

| # | Функция | Сложность | Приоритет |
|---|---------|-----------|-----------|
| 1 | check_kubernetes_specific | High | P1 |
| 2 | check_readiness_liveness | Medium | P1 |
| 3 | check_resource_limits | Medium | P1 |
| 4 | check_security_context | High | P1 |
| 5 | check_image_pull_policy | Low | P2 |
| 6 | check_service_type | Medium | P2 |
| 7 | check_probe_timeouts | Medium | P2 |
| 8 | check_affinity_rules | High | P2 |
| 9 | check_tolerations | Medium | P2 |
| 10 | check_node_selector | Low | P2 |
| 11 | check_volumes | High | P1 |
| 12 | check_persistent_volumes | Medium | P2 |
| 13 | check_config_map_references | Medium | P2 |
| 14 | check_secret_references | High | P1 |
| 15 | check_service_account | Medium | P2 |
| 16 | check_rbac | High | P1 |
| 17 | check_network_policy | High | P1 |
| 18 | check_ingress | Medium | P2 |
| 19 | check_hpa | Medium | P2 |
| 20 | check_pdb | Medium | P2 |
| 21-40 | ... (остальные K8s checks) | Various | P2-P3 |

### General YAML Checks (33 функции)

| # | Функция | Сложность | Приоритет |
|---|---------|-----------|-----------|
| 1 | check_line_length | Low | P2 |
| 2 | check_env_vars | Medium | P2 |
| 3 | check_annotations | Low | P2 |
| 4 | check_labels_format | Low | P2 |
| 5 | check_timestamps | Low | P3 |
| 6 | check_urls | Low | P3 |
| 7 | check_email | Low | P3 |
| 8-33 | ... (остальные general checks) | Low-Medium | P2-P3 |

---

## Implementation Plan

### Batch 4: High-Priority K8s (10 функций) — 2 часа с ИИ

**Функции:**
1. check_kubernetes_specific
2. check_readiness_liveness
3. check_resource_limits
4. check_security_context
5. check_volumes
6. check_secret_references
7. check_rbac
8. check_network_policy
9. check_service_type
10. check_probe_timeouts

**Процесс:**
```bash
# 1. Создать cached variants в lib/cached_checks.sh
# 2. Обновить call sites в yaml_validator.sh
# 3. Тестирование
./tests/test_fixer.sh
```

### Batch 5-10: Remaining Functions (63 функции) — 6 часов с ИИ

**Группировка по complexity:**
- **Simple (30 функций):** 2 часа
- **Medium (25 функций):** 2.5 часа  
- **Complex (8 функций):** 1.5 часа

---

## Expected Results

| Метрика | Current (27%) | Target (100%) | Improvement |
|---------|---------------|---------------|-------------|
| File reads per file | ~75 | 1 | **75x** reduction |
| Performance boost | +25% | +60-80% | **2.4-3.2x** total |
| Memory usage | ~120MB | ~180MB | +50% (acceptable) |

---

## Timeline

| Phase | Functions | Effort (с ИИ) | Status |
|-------|-----------|---------------|--------|
| **Phase 1A** | 9 | 2h | ✅ Done |
| **Phase 1B** | 18 | 3h | ✅ Done |
| **Phase 1C (Batch 4)** | 10 | 2h | 🔲 TODO |
| **Phase 1C (Batch 5-10)** | 63 | 6h | 🔲 TODO |
| **Total** | **100** | **13h** | **27% done** |

**Target completion:** v3.4.0 или отдельный patch v3.3.1

---

## Automation Strategy

### Option 1: Manual (Recommended for quality)
- Refactor каждую функцию вручную
- Review каждого batch
- **Pros:** Highest quality, full control
- **Cons:** 8 часов усилий

### Option 2: Semi-automated
- Использовать скрипт `scripts/refactor_check_functions.sh`
- Автогенерация cached variants
- Manual review + fixes
- **Pros:** Faster (4-5 часов)
- **Cons:** Может потребовать исправлений

### Option 3: Full automation (Not recommended)
- Полностью автоматическая генерация
- **Pros:** Fastest (1-2 часа)
- **Cons:** Potential bugs, low quality

**Рекомендация:** **Option 1** для production quality

---

## Testing Strategy

После каждого batch:
1. ✅ Syntax check: `bash -n yaml_validator.sh`
2. ✅ Unit tests: `./tests/test_fixer.sh` (41 тестов)
3. ✅ Performance benchmark: сравнить с baseline
4. ✅ Regression check: все функции работают идентично

---

## Decision

**Включать ли Phase 1C в v3.3.0?**
- **NO:** v3.3.0 уже даёт значительный прирост (36x с incremental)
- **YES:** Отложить на v3.3.1 или v3.4.0

**Рекомендация:** Выпустить v3.3.0 как есть (27% optimization), затем v3.3.1 с 100% optimization.

---

**Next:** Хотите ли запустить Phase 1C сейчас или в следующем релизе?
