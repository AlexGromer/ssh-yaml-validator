# Changelog

All notable changes to YAML Validator will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.2.0] - 2026-01-29

### Added - Full Autonomy (Phase 3)
- **Pure Bash Fallbacks**: Полная автономность — работает без внешних команд
  - `realpath_fallback()`: Канонизация путей (symlinks, .., ~)
  - `expand_fallback()`: Tabs → пробелы с обработкой ошибок
  - `od_fallback()`: Hex dump (fallback chain: od → xxd → pure bash)
  - `tput_compat()`: Wrapper для существующего 3-tier fallback
- **Fallback Library**: `lib/fallbacks.sh` с автоматической загрузкой
- Автоопределение: native command → fallback при отсутствии
- 43 unit/integration тестов для всех fallbacks
  - `tests/test_fallbacks.sh`: Comprehensive test suite
  - `tests/test_fallbacks_quick.sh`: Quick validation
  - `tests/test_minimal_quick.sh`: Minimal environment test
- Graceful degradation на всех уровнях

### Changed
- Все вызовы `realpath/expand/od/tput` → `*_compat` wrappers
- yaml_validator.sh: 4 замены (realpath, tput×2, od×2)
- fix_yaml_issues.sh: 3 замены (expand, od×2)
- **CRITICAL FIX**: Добавлена обработка ошибок для `expand` (риск повреждения файлов устранён)
  - fix_yaml_issues.sh:1281 теперь проверяет exit code перед `mv`

### Fixed
- **P1**: fix_yaml_issues.sh:1269 — expand может испортить файл при ошибке → добавлен error check
- Устранена зависимость от внешних команд (realpath, expand, od) для minimal systems

### Performance
- Fallback медленнее native (5-25x), но приемлемо для <100 файлов
- Оптимизация: xxd для od (10x быстрее pure bash)
- realpath_fallback: ~10ms per call (10 iterations in ~100ms)
- expand_fallback: ~200ms для 100 строк
- od_fallback: ~50ms per call with xxd, ~500ms pure bash

### Compatibility
- ✅ Работает на BusyBox (Alpine Linux, embedded)
- ✅ Air-gapped environments (закрытые контуры)
- ✅ Older Linux (без modern utils)
- ✅ Astra Linux SE 1.7 (Smolensk)

### Documentation
- README.md: Новая секция "Зависимости" с fallback matrix
- CHANGELOG.md: Создан файл истории изменений

---

## [3.1.0] - 2026-01-29

### Added
- 17 новых Kubernetes auto-fixes
  - E2: Add `privileged: false`
  - E3: Add `runAsNonRoot: true`
  - E4: Add `readOnlyRootFilesystem: true`
  - E7: Create NetworkPolicy companion file
  - E9: Add `capabilities.drop: [ALL]`
  - E13-E17: Best practice fixes (labels, annotations, probes)
  - E18-E20: HA fixes (PDB, affinity, topology)
  - E21-E24: Resource fixes (limits, requests, quotas)
- **Batch Mode**: Config file support (`-c/--config`)
  - `.fixerrc` format for non-interactive operations
  - Example: `config.namespace=production`
- Integration tests for all new fixes (41 tests total)

### Changed
- Fixer version: 3.0.0 → 3.1.0
- Test coverage: 13 → 41 tests

---

## [3.0.0] - 2026-01-29

### Added
- **Live Output Window** (`--live`): Интерактивный режим с прогресс-баром
  - Real-time output в scrollable window (F2 pause, arrows scroll)
  - Progress bar с файлами и severity counts
  - HTML export (`--live-report html`)
  - ANSI-совместимая реализация (работает без ncurses)
- 134 проверки (A-E categories)
- Severity levels system (ERROR, WARNING, INFO, SECURITY)
- Security modes (strict, normal, permissive)

### Changed
- Validator version: 2.9.0 → 3.0.0
- Architecture: Modular design с fallback functions

---

## [2.9.0] - 2026-01-28

### Added
- Initial release with 134 validation checks
- Auto-fix functionality (13 types)
- Joint mode (validator + fixer integration)
- JSON output mode
- Test coverage: 99.7%

### Security
- 30 K8s security checks
- 3 audit trail hooks (security_audit.log, infra_audit.log, helm_audit.log)

---

[3.2.0]: https://github.com/AlexGromer/ssh-yaml-validator/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/AlexGromer/ssh-yaml-validator/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/AlexGromer/ssh-yaml-validator/compare/v2.9.0...v3.0.0
[2.9.0]: https://github.com/AlexGromer/ssh-yaml-validator/releases/tag/v2.9.0

## [3.3.1] - 2026-01-30

### Added - Performance Optimization Phase 1C (100% Function Coverage)
- **95 cached check functions** (up from 28 in v3.3.0)
- File I/O reduction: **94%** (101 → 6 reads per validation)
- Performance improvement: **2-2.4x cumulative speedup**
- 67 additional functions optimized:
  - 10 high-priority K8s security functions
  - 41 K8s resource validation functions
  - 16 general YAML formatting functions

### Added - Automated Testing
- Performance benchmarks: `tests/performance/run_all.sh`
  - Baseline, parallel, incremental benchmarks
  - Automated assertions (5x parallel, 30x incremental targets)
- Security tests: `tests/security/run_all_security.sh`
  - Command injection tests (4 tests)
  - Path traversal tests (4 tests)
  - Secrets detection tests (4 tests)
  - Total: 12/12 security tests PASS

### Performance
- Sequential validation: 121s → ~100s (**17% faster**)
- Parallel mode: 18s → ~15s (6.7x vs baseline)
- Incremental (2nd run): 2s → ~1.5s (60x vs baseline)
- Memory overhead: +50% (acceptable for typical workloads)

### Changed
- `lib/cached_checks.sh`: 1,299 → 5,104 lines (+3,805 lines, +293%)
- `yaml_validator.sh`: Updated 95 call sites for cached functions

### Fixed
- Syntax errors in call site patterns (3 locations)
- Test suite compatibility (removed bc dependency, use bash arithmetic)

### Testing
- Regression tests: 41/41 PASS (100%)
- Security tests: 12/12 PASS (100%)
- Performance benchmarks: All targets exceeded

### Documentation
- Added `docs/PHASE1C_IMPLEMENTATION_REPORT.md` (comprehensive 286-line report)
- Updated performance metrics in README.md
- Marked Phase 5 complete in ROADMAP.md
