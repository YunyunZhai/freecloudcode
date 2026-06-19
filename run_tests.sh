#!/bin/bash
# run_tests.sh — 运行所有测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 FreeCloudCode 测试套件"
echo "========================================="

# 测试文件列表
TEST_FILES=(
    "tests/test_utils_functions.sh"
    "tests/test_install.sh"
    "tests/test_start.sh"
    "tests/test_status.sh"
)

TOTAL_PASSED=0
TOTAL_FAILED=0
ALL_TESTS_RUN=0
ALL_TESTS_PASSED=0
ALL_TESTS_FAILED=0

for test_file in "${TEST_FILES[@]}"; do
    echo ""
    echo "📝 测试: $(basename "$test_file")"
    echo "-----------------------------------------"

    if bash "$SCRIPT_DIR/$test_file" 2>&1; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
done

echo ""
echo "========================================="
echo "📊 最终结果: $TOTAL_PASSED 通过, $TOTAL_FAILED 失败"
echo "========================================="

if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "\033[0;32m✅ 所有测试通过！\033[0m"
    exit 0
else
    echo -e "\033[0;31m❌ 有测试失败\033[0m"
    exit 1
fi
