#!/bin/bash
# tests/test_utils_functions.sh — utils.sh 函数测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_utils.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

# 测试: check_command 检查存在的命令
test_check_command_exists() {
    assert_true "check_command bash"
}

# 测试: check_command 检查不存在的命令
test_check_command_not_exists() {
    assert_true "! check_command nonexistent_command_xyz"
}

# 测试: check_file 检查存在的文件
test_check_file_exists() {
    local tmpfile="/tmp/fcc_test_file_$$.txt"
    touch "$tmpfile"
    assert_true "check_file '$tmpfile'"
    rm -f "$tmpfile"
}

# 测试: check_file 检查不存在的文件
test_check_file_not_exists() {
    assert_true "! check_file '/tmp/nonexistent_fcc_test_$$.txt'"
}

# 测试: ensure_dir 创建目录
test_ensure_dir() {
    local tmpdir="/tmp/fcc_test_dir_$$"
    rm -rf "$tmpdir"
    ensure_dir "$tmpdir"
    assert_dir_exists "$tmpdir"
    rm -rf "$tmpdir"
}

# 测试: get_tailscale_ip 返回 IP 或空
test_get_tailscale_ip() {
    local result
    result=$(get_tailscale_ip)
    # 返回值应该是 IP 或空
    [[ -z "$result" ]] || [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# 运行测试
run_test "check_command 存在" "test_check_command_exists"
run_test "check_command 不存在" "test_check_command_not_exists"
run_test "check_file 存在" "test_check_file_exists"
run_test "check_file 不存在" "test_check_file_not_exists"
run_test "ensure_dir 创建目录" "test_ensure_dir"
run_test "get_tailscale_ip 返回格式" "test_get_tailscale_ip"

# 显示结果
echo "========================================="
echo "📊 测试结果:"
echo "  运行: $TESTS_RUN"
echo -e "  ${GREEN}通过: $TESTS_PASSED${NC}"
echo -e "  ${RED}失败: $TESTS_FAILED${NC}"

[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
