#!/bin/bash
# tests/test_install.sh — install.sh 函数测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_utils.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/install.sh"

# 测试: configure_claude_code_hooks 创建设置文件
test_configure_claude_code_hooks() {
    local test_home="/tmp/fcc_test_home_$$"
    mkdir -p "$test_home/.claude"
    local original_home="$HOME"
    export HOME="$test_home"

    configure_claude_code_hooks

    assert_file_exists "$test_home/.claude/settings.json"

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

run_test "configure_claude_code_hooks" "test_configure_claude_code_hooks"
run_test "create_directories" "test_create_directories"

echo "========================================="
echo "📊 测试结果: $TESTS_RUN 运行, ${GREEN}$TESTS_PASSED 通过${NC}, ${RED}$TESTS_FAILED 失败${NC}"
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
