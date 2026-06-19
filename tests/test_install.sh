#!/bin/bash
# tests/test_install.sh — install.sh 函数测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_utils.sh"
source "$SCRIPT_DIR/../lib/install.sh"

# 测试: ensure_dir 创建目录
test_install_ensure_dir() {
    local tmpdir="/tmp/fcc_test_install_$$"
    rm -rf "$tmpdir"
    ensure_dir "$tmpdir"
    assert_dir_exists "$tmpdir"
    rm -rf "$tmpdir"
}

# 测试: configure_claude_code_hooks 创建设置文件
test_configure_claude_code_hooks() {
    local test_home="/tmp/fcc_test_home_$$"
    mkdir -p "$test_home/.claude"

    # 临时修改 HOME
    local original_home="$HOME"
    export HOME="$test_home"

    # 运行函数
    configure_claude_code_hooks

    # 验证文件创建
    assert_file_exists "$test_home/.claude/settings.json"

    # 恢复 HOME
    export HOME="$original_home"
    rm -rf "$test_home"
}

# 测试: create_directories 创建目录结构
test_create_directories() {
    local test_home="/tmp/fcc_test_dirs_$$"
    mkdir -p "$test_home"

    local original_home="$HOME"
    export HOME="$test_home"

    create_directories

    assert_dir_exists "$test_home/.freecloudcode/logs"
    assert_dir_exists "$test_home/.freecloudcode/config"

    export HOME="$original_home"
    rm -rf "$test_home"
}

# 运行测试
run_test "ensure_dir 创建目录" "test_install_ensure_dir"
run_test "configure_claude_code_hooks" "test_configure_claude_code_hooks"
run_test "create_directories" "test_create_directories"

# 显示结果
echo "========================================="
echo "📊 测试结果:"
echo "  运行: $TESTS_RUN"
echo -e "  ${GREEN}通过: $TESTS_PASSED${NC}"
echo -e "  ${RED}失败: $TESTS_FAILED${NC}"

[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
