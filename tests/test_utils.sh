#!/bin/bash
# tests/test_utils.sh — 测试框架（仅定义，不执行）

# 测试计数
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=()

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 运行单个测试
run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if eval "$test_func" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILURES+=("$test_name")
        echo -e "${RED}✗${NC} $test_name"
    fi
}

# 断言函数
assert_true() {
    local condition="$1"
    eval "$condition"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    [ "$expected" = "$actual" ]
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    echo "$haystack" | grep -q "$needle"
}

assert_file_exists() {
    local file="$1"
    [ -f "$file" ]
}

assert_dir_exists() {
    local dir="$1"
    [ -d "$dir" ]
}

# 运行所有测试
run_tests() {
    local test_file="$1"

    echo ""
    echo "🧪 运行测试..."
    echo "========================================="

    # 加载测试函数
    source "$test_file"

    echo "========================================="
    echo "📊 测试结果:"
    echo "  运行: $TESTS_RUN"
    echo -e "  ${GREEN}通过: $TESTS_PASSED${NC}"
    echo -e "  ${RED}失败: $TESTS_FAILED${NC}"

    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}失败的测试:${NC}"
        for failure in "${FAILURES[@]}"; do
            echo "  - $failure"
        done
        return 1
    fi

    return 0
}
