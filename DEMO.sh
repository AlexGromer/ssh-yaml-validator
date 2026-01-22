#!/bin/bash
# Демонстрация работы YAML Validator

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║           ДЕМОНСТРАЦИЯ YAML VALIDATOR v1.0.0                          ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "═══ СЦЕНАРИЙ 1: Проверка тестовых файлов ═══"
echo ""
./yaml_validator.sh test_samples/
echo ""
read -p "Нажмите Enter для продолжения..."
echo ""

echo "═══ СЦЕНАРИЙ 2: Автоматическое исправление (dry-run) ═══"
echo ""
./fix_yaml_issues.sh --dry-run test_samples/
echo ""
read -p "Нажмите Enter для продолжения..."
echo ""

echo "═══ СЦЕНАРИЙ 3: Реальное исправление с backup ═══"
echo ""
rm -rf test_demo
cp -r test_samples test_demo
./fix_yaml_issues.sh -b test_demo/
echo ""
read -p "Нажмите Enter для продолжения..."
echo ""

echo "═══ СЦЕНАРИЙ 4: Проверка после исправления ═══"
echo ""
./yaml_validator.sh test_demo/
echo ""

echo "═══ ДЕМОНСТРАЦИЯ ЗАВЕРШЕНА ═══"
echo ""
echo "Результаты:"
echo "  - Исходные файлы: test_samples/"
echo "  - Исправленные:   test_demo/"
echo ""
echo "Для очистки выполните: rm -rf test_demo"
