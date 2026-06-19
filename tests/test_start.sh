#!/bin/bash
# tests/test_start.sh — start.sh 函数测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_utils.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/start.sh"

# 测试: record 函数记录状态
test_record_function() {
    SvcName=(); SvcStatus=(); SvcLog=(); SvcHint=()
    record "TestService" "ok" "/tmp/test.log" "测试状态"
    assert_equals "TestService" "${SvcName[0]}"
    assert_equals "ok" "${SvcStatus[0]}"
    assert_equals "/tmp/test.log" "${SvcLog[0]}"
    assert_equals "测试状态" "${SvcHint[0]}"
}

# 测试: generate_status_report 创建文件
test_generate_status_report() {
    SvcName=("Svc1"); SvcStatus=("ok"); SvcLog=(""); SvcHint=("运行中")
    generate_status_report
    assert_file_exists "$HOME/.freecloudcode/startup-status.log"
}

run_test "record 函数" "test_record_function"
run_test "generate_status_report" "test_generate_status_report"

echo "========================================="
echo "📊 测试结果: $TESTS_RUN 运行, ${GREEN}$TESTS_PASSED 通过${NC}, ${RED}$TESTS_FAILED 失败${NC}"
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
