#!/bin/bash
# tests/test_start.sh — start.sh 函数测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_utils.sh"
source "$SCRIPT_DIR/../lib/start.sh"

# 测试: record 函数记录状态
test_record_function() {
    # 清空数组
    SvcName=()
    SvcStatus=()
    SvcLog=()
    SvcHint=()

    # 记录一个服务
    record "TestService" "ok" "/tmp/test.log" "测试状态"

    assert_equals "TestService" "${SvcName[0]}"
    assert_equals "ok" "${SvcStatus[0]}"
    assert_equals "/tmp/test.log" "${SvcLog[0]}"
    assert_equals "测试状态" "${SvcHint[0]}"
}

# 测试: generate_status_report 创建状态文件
test_generate_status_report() {
    local test_status="/tmp/fcc_test_status_$$"
    local original_status="$STATUS_FILE"
    STATUS_FILE="$test_status"

    # 清空数组并添加测试数据
    SvcName=("Service1" "Service2")
    SvcStatus=("ok" "fail")
    SvcLog=("" "/tmp/test.log")
    SvcHint=("运行正常" "启动失败")

    generate_status_report

    assert_file_exists "$test_status"

    STATUS_FILE="$original_status"
    rm -f "$test_status"
}

# 运行测试
run_test "record 函数记录状态" "test_record_function"
run_test "generate_status_report 创建文件" "test_generate_status_report"

# 显示结果
echo "========================================="
echo "📊 测试结果:"
echo "  运行: $TESTS_RUN"
echo -e "  ${GREEN}通过: $TESTS_PASSED${NC}"
echo -e "  ${RED}失败: $TESTS_FAILED${NC}"

[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
