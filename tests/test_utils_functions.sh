#!/bin/bash
# tests/test_utils_functions.sh — utils.sh 函数测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_utils.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

# 测试: check_command
test_check_command_exists() { assert_true "check_command bash"; }
test_check_command_not_exists() { assert_true "! check_command nonexistent_xyz"; }

# 测试: check_file
test_check_file_exists() {
    local f="/tmp/fcc_test_$$.txt"; touch "$f"
    assert_true "check_file '$f'"; rm -f "$f"
}
test_check_file_not_exists() { assert_true "! check_file '/tmp/nonexistent_fcc_$$.txt'"; }

# 测试: ensure_dir
test_ensure_dir() {
    local d="/tmp/fcc_test_dir_$$"; rm -rf "$d"
    ensure_dir "$d"; assert_dir_exists "$d"; rm -rf "$d"
}

# 测试: http_check（验证函数语法和参数处理）
test_http_check() {
    # 用不存在的地址验证返回 false（不超时崩溃）
    assert_true "! http_check 'http://192.0.2.1:1' 1"
}

# 测试: http_check_retry（验证重试逻辑）
test_http_check_retry() {
    # 不存在的地址应重试后返回 false
    assert_true "! http_check_retry 'http://192.0.2.1:1' 2 1 1"
}

# 测试: is_service_running
test_is_service_running_not() {
    assert_true "! is_service_running nonexistent_service_xyz nonexistent_cmd_xyz"
}

# 测试: tailscale_ip
test_tailscale_ip() {
    local ip; ip=$(tailscale_ip)
    [[ -z "$ip" ]] || [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# 测试: display_status_line
test_display_status_line_ok() {
    local out; out=$(display_status_line "ok" "Test" "Running")
    assert_contains "$out" "✅"
    assert_contains "$out" "Test"
}

test_display_status_line_fail() {
    local out; out=$(display_status_line "fail" "Test" "Error")
    assert_contains "$out" "❌"
}

# 测试: query_tailscale 输出格式
test_query_tailscale_format() {
    local out; out=$(query_tailscale)
    [[ "$out" =~ ^(ok|fail|skip)\|Tailscale\|.+$ ]]
}

# 测试: 常量已定义
test_constants() {
    assert_true "[ -n '$SETUP_MARKER' ]"
    assert_true "[ -n '$STARTUP_MARKER' ]"
    assert_true "[ -n '$LOG_DIR' ]"
}

run_test "check_command 存在" "test_check_command_exists"
run_test "check_command 不存在" "test_check_command_not_exists"
run_test "check_file 存在" "test_check_file_exists"
run_test "check_file 不存在" "test_check_file_not_exists"
run_test "ensure_dir 创建目录" "test_ensure_dir"
run_test "http_check" "test_http_check"
run_test "http_check_retry" "test_http_check_retry"
run_test "is_service_running 不存在" "test_is_service_running_not"
run_test "tailscale_ip 格式" "test_tailscale_ip"
run_test "display_status_line ok" "test_display_status_line_ok"
run_test "display_status_line fail" "test_display_status_line_fail"
run_test "query_tailscale 格式" "test_query_tailscale_format"
run_test "常量已定义" "test_constants"

echo "========================================="
echo "📊 测试结果: $TESTS_RUN 运行, ${GREEN}$TESTS_PASSED 通过${NC}, ${RED}$TESTS_FAILED 失败${NC}"
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
