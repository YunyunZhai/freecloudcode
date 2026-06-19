#!/bin/bash
# tests/test_status.sh — status.sh 函数测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_utils.sh"
source "$SCRIPT_DIR/../lib/status.sh"

# 测试: show_status 函数存在
test_show_status_exists() {
    type show_status >/dev/null 2>&1
}

# 测试: wait_for_startup 函数存在
test_wait_for_startup_exists() {
    type wait_for_startup >/dev/null 2>&1
}

# 测试: show_commands 函数存在
test_show_commands_exists() {
    type show_commands >/dev/null 2>&1
}

# 运行测试
run_test "show_status 函数存在" "test_show_status_exists"
run_test "wait_for_startup 函数存在" "test_wait_for_startup_exists"
run_test "show_commands 函数存在" "test_show_commands_exists"

# 显示结果
echo "========================================="
echo "📊 测试结果:"
echo "  运行: $TESTS_RUN"
echo -e "  ${GREEN}通过: $TESTS_PASSED${NC}"
echo -e "  ${RED}失败: $TESTS_FAILED${NC}"

[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
