#!/usr/bin/env bash
# =============================================================================
# 更新预编译样式兜底文件
# -----------------------------------------------------------------------------
# 背景见 layouts/_partials/head/style.html。
#
# 简言之：Cloudflare 的 Hugo 是标准版，编译不了 SCSS。正常情况由
# bin/build.sh 安装 Dart Sass 解决；万一装不上，构建会回退到
# assets/scss/prebuilt.css。
#
# 那份 prebuilt.css 是提前编译好的快照。**只要你改了 SCSS，就要重新生成它**，
# 否则一旦走到兜底分支，线上样式就是旧的。
#
# 用法：
#     bash bin/update-prebuilt.sh
#
# 需要本地 Hugo 是 extended 版（hugo version 里带 +extended）。
# =============================================================================

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v hugo >/dev/null 2>&1; then
    echo "ERROR: 找不到 hugo" >&2
    exit 1
fi

if ! hugo version | grep -q '+extended'; then
    echo "ERROR: 需要 Hugo extended 版才能编译 SCSS" >&2
    echo "       当前: $(hugo version)" >&2
    exit 1
fi

echo "==> 编译 SCSS"

TMP_OUT="$(mktemp -d)"
trap 'rm -rf "${TMP_OUT}"' EXIT

hugo --minify --destination "${TMP_OUT}" >/dev/null

# 找编译出的样式文件（排除 sass 源码拷贝）
CSS_FILE="$(find "${TMP_OUT}/scss" -name '*.css' -type f | head -n 1)"

if [ -z "${CSS_FILE}" ] || [ ! -s "${CSS_FILE}" ]; then
    echo "ERROR: 没有找到编译产物" >&2
    exit 1
fi

cp "${CSS_FILE}" assets/scss/prebuilt.css

SIZE="$(wc -c < assets/scss/prebuilt.css)"
echo "==> 已更新 assets/scss/prebuilt.css (${SIZE} bytes)"
echo
echo "记得一并提交："
echo "    git add assets/scss/prebuilt.css"
echo "    git commit -m 'update prebuilt css'"
