#!/bin/bash
# tests/test_status.sh — status.sh 函数测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_utils.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/status.sh"

# 测试: show_status 函数存在
test_show_status_exists() { type show_status >/dev/null 2>&1; }

# 测试: wait_for_startup 函数存在
test_wait_for_startup_exists() { type wait_for_startup >/dev/null 2>&1; }

run_test "show_status 函数存在" "test_show_status_exists"
run_test "wait_for_startup 函数存在" "test_wait_for_startup_exists"

echo "========================================="
echo "📊 测试结果: $TESTS_RUN 运行, ${GREEN}$TESTS_PASSED 通过${NC}, ${RED}$TESTS_FAILED 失败${NC}"
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
