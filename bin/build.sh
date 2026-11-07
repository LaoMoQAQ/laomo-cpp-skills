#!/usr/bin/env bash
# =============================================================================
# Cloudflare Workers 构建脚本
# -----------------------------------------------------------------------------
# 【问题】
# Cloudflare 构建镜像预装的 Hugo 是「标准版」（版本号无 +extended），
# 它没有内置 libsass，无法编译 SCSS。Stack 主题的样式入口
# assets/scss/style.scss 需要编译，于是构建失败：
#
#   TOCSS: failed to transform "/scss/style.scss" (text/x-scss).
#   Check your Hugo installation; you need the extended version to build
#   SCSS/SASS with transpiler set to 'libsass'
#
# 【为什么以前没暴露】
# 仓库里曾误提交 resources/_gen/ 编译缓存，Hugo 命中缓存就跳过 SCSS 编译。
# 缓存一旦清理，问题立刻出现。
#
# 【本脚本做的事】
# 1. 安装 Dart Sass，让标准版 Hugo 也能编译 SCSS（dartsass 转译器）
# 2. 设置 HUGO_SASS_TRANSPILER=dartsass，让覆盖的 style.html 使用它
# 3. 尝试安装 extended Hugo 作为更优选择（自带 libsass）
# 4. 执行 hugo --minify
#
# 【用法】
# Cloudflare 面板 → 构建设置 → 构建命令，把
#     hugo --minify
# 改成
#     bash bin/build.sh
# =============================================================================

set -euo pipefail

HUGO_VERSION="${HUGO_VERSION:-0.168.0}"
SASS_VERSION="${SASS_VERSION:-1.80.4}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# 下载工具：curl 优先，退化到 wget
fetch() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 2 --max-time 300 -o "${out}" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "${out}" "${url}"
    else
        echo "ERROR: 构建环境既没有 curl 也没有 wget" >&2
        return 1
    fi
}

# ------------------------------------------------ 1. Dart Sass（标准版可用）
echo "==> 安装 Dart Sass ${SASS_VERSION}"
SASS_TGZ="${TMP_DIR}/sass.tar.gz"
SASS_URL="https://github.com/sass/dart-sass/releases/download/${SASS_VERSION}/dart-sass-${SASS_VERSION}-linux-x64.tar.gz"
SASS_OK=0

if fetch "${SASS_URL}" "${SASS_TGZ}" 2>/dev/null; then
    tar -xzf "${SASS_TGZ}" -C "${TMP_DIR}"
    if [ -x "${TMP_DIR}/dart-sass/sass" ]; then
        export PATH="${TMP_DIR}/dart-sass:${PATH}"
        echo "    OK: $(sass --version)"
        SASS_OK=1
    fi
fi

if [ "${SASS_OK}" -eq 1 ]; then
    export HUGO_SASS_TRANSPILER=dartsass
    echo "    转译器: dartsass"
else
    echo "    WARN: Dart Sass 安装失败，将依赖 extended Hugo 的 libsass" >&2
    export HUGO_SASS_TRANSPILER=libsass
    echo "    转译器: libsass"
fi

# ------------------------------------------ 2. extended Hugo（若下载成功更优）
echo "==> 尝试安装 Hugo extended ${HUGO_VERSION}"
HUGO_TGZ="${TMP_DIR}/hugo.tar.gz"
HUGO_URL="https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz"

if fetch "${HUGO_URL}" "${HUGO_TGZ}" 2>/dev/null; then
    mkdir -p "${TMP_DIR}/hugo-ext"
    tar -xzf "${HUGO_TGZ}" -C "${TMP_DIR}/hugo-ext"
    if [ -x "${TMP_DIR}/hugo-ext/hugo" ] && "${TMP_DIR}/hugo-ext/hugo" version | grep -q '+extended'; then
        export PATH="${TMP_DIR}/hugo-ext:${PATH}"
        echo "    OK: $("${TMP_DIR}/hugo-ext/hugo" version)"
    fi
else
    echo "    WARN: extended Hugo 下载失败，使用镜像自带版本" >&2
fi

# ------------------------------------------------------------- 3. 构建
if ! command -v hugo >/dev/null 2>&1; then
    echo "ERROR: 找不到 hugo 可执行文件" >&2
    exit 1
fi

echo "==> 使用 $(hugo version)"
echo "==> HUGO_SASS_TRANSPILER=${HUGO_SASS_TRANSPILER}"
echo "==> 开始构建"
hugo --minify "$@"
echo "==> 构建完成"
