# 博客实现与部署说明

> 站点：<https://laomo-cpp-skills.laomo-qaq-qaq.workers.dev/>
> 仓库：<https://github.com/LaoMoQAQ/laomo-cpp-skills>
> 本文记录这套博客**是怎么搭起来、怎么构建、怎么上线**的，以及踩过的坑。

---

## 0. 一句话总览

Hugo 生成静态站点 → 推到 GitHub `main` → Cloudflare Workers 自动拉代码、跑 `hugo --minify`、用 `wrangler` 把 `public/` 当静态资源上传。

```
本地 G:\My blog
   │  hugo server（本地预览）
   │  git commit / git push（走 Clash 代理 7890）
   ▼
GitHub  LaoMoQAQ/laomo-cpp-skills  (main 分支)
   │  Cloudflare 监听 main 分支的 push
   ▼
Cloudflare Workers 构建环境
   │  1. git clone + 拉取 submodule（主题）
   │  2. 安装 Hugo（pin 0.168.0）
   │  3. 执行 hugo --minify  → 产出 public/
   │  4. npx wrangler deploy  → 上传 public/ 作为静态资源
   ▼
https://laomo-cpp-skills.laomo-qaq-qaq.workers.dev/
```

**技术栈**

| 项目 | 版本 / 说明 |
| --- | --- |
| 静态生成器 | Hugo **0.168.0 extended**（本地） |
| 主题 | [Hugo Theme Stack](https://github.com/CaiJimmy/hugo-theme-stack) **v4.0.3** |
| 主题引入方式 | git submodule，固定在 `3e123a3` |
| 托管 | Cloudflare **Workers**（不是 Pages） |
| 本地环境 | Windows + PowerShell，Git 走 Clash 代理 `127.0.0.1:7890` |

---

# 第一部分：GitHub 板块

## 1.1 分支策略

只有 `main` 一个长期分支，直接推。Cloudflare 监听 `main` 的 push，推上去就自动构建部署。

```powershell
git add -A
git commit -m "说明"
git push origin main
```

因为网络原因，push 要带代理：

```powershell
git -c http.proxy=http://127.0.0.1:7890 `
    -c https.proxy=http://127.0.0.1:7890 `
    push origin main
```

> 偶尔会报 `TLS connect error: unexpected eof while reading`，是代理抖动，重试两三次即可，不是仓库问题。

## 1.2 目录结构与每个文件的职责

```
G:\My blog\
├─ hugo.toml                    主配置（语言、菜单、高亮、评论）
├─ wrangler.toml                Cloudflare Workers 部署配置
├─ .gitignore                   排除构建产物
├─ .gitattributes               强制脚本 LF、字体 binary
├─ .gitmodules                  主题 submodule 定义
│
├─ content\                     文章
│  └─ cpp\
│     ├─ _index.md              分类首页（标题「C++ 资源库」）
│     └─ csp-bancs.md           CSP-J/S 算法板子
│
├─ assets\scss\
│  ├─ custom.scss               ★ 全部自定义样式（覆盖主题）
│  └─ prebuilt.css              ★ 编译好的样式快照（构建兜底用）
│
├─ layouts\_partials\head\
│  ├─ style.html                ★ 覆盖主题：SCSS 三级降级编译
│  └─ custom-font.html          ★ 覆盖主题：去掉 Google Fonts 外链
│
├─ bin\
│  ├─ build.sh                  ★ Cloudflare 构建脚本（可选但推荐）
│  └─ update-prebuilt.sh        ★ 改完 SCSS 后重新生成 prebuilt.css
│
├─ static\
│  ├─ favicon.ico
│  └─ fonts\                    ★ 自托管 JetBrains Mono
│     ├─ jetbrains-mono-latin-400.woff2
│     └─ jetbrains-mono-latin-700.woff2
│
├─ themes\hugo-theme-stack\     ← submodule，不要手改
│
├─ public\                      ← 构建产物，已 gitignore
└─ resources\_gen\              ← Hugo 资源缓存，已 gitignore
```

带 ★ 的是本项目自己加的，其余是 Hugo 约定或主题自带。

> **重要**：`themes/hugo-theme-stack/` 是 git submodule，**任何对主题的修改都会被 `git submodule update` 冲掉**。
> 要改主题行为，一律用「在 `layouts/` 下放同名覆盖文件」的方式，Hugo 会优先用项目根目录的版本。

## 1.3 主题为什么用 submodule

Hugo 找主题的顺序是 `themes/<theme>/`，Cloudflare 构建时也要能拿到这份主题代码。
用 submodule 的好处是：主题代码不进主仓库，体积小，且版本锁定。

```ini
# .gitmodules
[submodule "themes/hugo-theme-stack"]
	path = themes/hugo-theme-stack
	url = https://github.com/CaiJimmy/hugo-theme-stack.git
```

**代价**：克隆时必须带 `--recurse-submodules`，否则主题目录是空的。

```powershell
# 首次克隆
git clone --recurse-submodules https://github.com/LaoMoQAQ/laomo-cpp-skills.git

# 已经克隆过，补拉主题
git submodule update --init --recursive
```

Cloudflare 那边是会拉 submodule 的，这点已由线上正常运行验证过。

当前锁定版本：

```powershell
$ git submodule status
 3e123a30b79b5d52a3a8e88a9dd678fcfd28e418 themes/hugo-theme-stack (v4.0.3)
```

## 1.4 为什么 `public/` 必须 gitignore

这是踩过的一个真实事故。

**现象**：`content/cpp/learncpp.md` 早就删了（提交 `343d79e`），但线上 `/cpp/learncpp/` 一直能访问，返回 200。

**原因**：`public/` 被提交进了仓库。Cloudflare 构建时先 `git clone`（此时仓库里带着**旧的** `public/`），再跑 `hugo --minify`。Hugo 默认**不会删除**目标目录里多余的文件，于是旧的 `learncpp/index.html` 被原样保留，一起上传上线。

雪上加霜的是，仓库里那份 `public/` 其实是本地 `hugo server` 的开发产物——里面带着 `livereload.js` 和 `localhost:1313` 的链接，根本不是能上线的版本。

**修复**：

```gitignore
public/
resources/_gen/
```

```powershell
git rm -r --cached public resources .hugo_build.lock
```

`resources/_gen/` 一起排除——它还有另一个副作用，见第二部分 2.3。

## 1.5 `.gitattributes`：两个必须写死的规则

```gitattributes
# 构建脚本必须在 Linux 下用 LF 换行
bin/*.sh   text eol=lf

# 字体是二进制，别让 Git 做任何换行转换
*.woff2    binary
*.woff     binary
*.ico      binary
```

**为什么必须加**：本机 `core.autocrlf=true`。Git 默认会把 `.sh` 里的 LF 转成 CRLF 提交。一旦脚本变成 CRLF，在 Linux 构建机上 bash 会报：

```
$'\r': command not found
```

这种错误信息极具误导性，看起来像是脚本语法错误。加了 `eol=lf` 后，仓库里存的永远是 LF。

验证方法：

```powershell
# 直接读 git 索引里的版本，而不是工作区
git show :bin/build.sh > "$env:TEMP\check.sh"
$b = [System.IO.File]::ReadAllBytes("$env:TEMP\check.sh")
```

## 1.6 关键提交一览

| 提交 | 内容 |
| --- | --- |
| `d5a5252` | 修复 Cloudflare 构建失败：覆盖 `style.html`，改用 `css.Sass` |
| `2fdb960` | 三级降级 + `prebuilt.css` 兜底 + `bin/` 脚本 |
| `560dbf6` | 代码块字号叠加、清理残留页、修复语言/日期配置 |
| `d34c6ab` | 复制按钮显示策略（触屏常驻） |
| `7e9d1e8` | 收窄页面宽度、下调字号，避免贴边 |

## 1.7 本地开发流程

```powershell
cd "G:\My blog"

# 预览（带草稿、热更新），访问 http://localhost:1313/
hugo server -D

# 构建生产版本（和 Cloudflare 用同一条命令）
hugo --minify
```

**改样式后的固定动作**：

```powershell
# 1. 改 assets/scss/custom.scss
# 2. 本地看一眼
hugo server -D
# 3. ★ 重新生成兜底快照（否则线上可能用到旧样式，见 2.4）
bash bin/update-prebuilt.sh
# 4. 提交
git add -A; git commit -m "..."; git push origin main
```

## 1.8 新增文章 / 新增分类

**新增文章**（放在已有分类下）：

```
content/cpp/新文章.md
```

```yaml
---
title: "标题"
description: "一句话摘要"
date: 2026-11-23
math: true
tags: ["C++", "算法"]
---
```

`math: true` 开启该页的 KaTeX 公式渲染。

**新增分类**：

1. 建目录 `content/新分类/`
2. 建 `_index.md`：

```yaml
---
title: "新分类名"
layout: "list"
---
```

3. 在 `hugo.toml` 的 `mainSections` 里加上，否则首页不显示该分类的文章：

```toml
[params]
  mainSections = ["cpp", "新分类"]
```

---

# 第二部分：Cloudflare 板块

## 2.1 部署模式：Workers，不是 Pages

这个站用的是 **Cloudflare Workers + 静态资源绑定**，不是 Pages。区别很关键：

- 构建命令里用的是 `npx wrangler deploy`，靠根目录的 `wrangler.toml` 决定上传哪个目录
- 静态资源目录由 `wrangler.toml` 的 `[assets] directory` 指定

```toml
# wrangler.toml
name = "laomo-cpp-skills"
compatibility_date = "2024-04-05"

[assets]
directory = "./public"
```

也就是说：**Hugo 只管往 `public/` 里生成，wrangler 负责把 `public/` 发布出去。**

## 2.2 构建配置

Cloudflare 面板 → Workers 和 Pages → `laomo-cpp-skills` → 设置 → 构建：

| 配置项 | 值 |
| --- | --- |
| 构建命令 | `hugo --minify`（**推荐改成 `bash bin/build.sh`**，见 2.5） |
| 部署命令 | `npx wrangler deploy` |
| 根目录 | `/` |
| 构建变量 | `HUGO_VERSION` = `0.168.0` |

触发方式：`main` 分支 push 后自动构建。构建大约 40 秒环境初始化 + 几秒编译。

## 2.3 核心故障：Cloudflare 的 Hugo 是「标准版」

这是整个项目最坑的一个问题，值得完整记录。

### 现象

构建失败，红色 `最近的构建失败`，日志停在这样一行下面：

```
10:56:42.706  hugo v0.168.0-...  linux/amd64   BuildDate=...   VendorInfo=gohugoio
10:56:42.706  WARN  deprecated: css.Sass: libsass was deprecated in Hugo v0.153.0 ...
```

真正的错误在 WARN 下面，被日志滚屏挡住了。

### 定位

注意版本号里**没有 `+extended`**：

```
Cloudflare:  hugo v0.168.0-e27a676...  linux/amd64
本地:        hugo v0.168.0-e27a676...+extended windows/amd64
```

Stack 主题的样式入口是 `assets/scss/style.scss`，主题原本用 `toCSS` 编译它：

```go-html-template
{{ $sass := resources.Get "scss/style.scss" }}
{{ $style := $sass | toCSS | minify | resources.Fingerprint "sha256" }}
```

`toCSS` 走 **libsass**，而 **libsass 只存在于 Hugo extended 版**。标准版没有它，于是：

```
TOCSS: failed to transform "/scss/style.scss" (text/x-scss).
Check your Hugo installation; you need the extended version to build
SCSS/SASS with transpiler set to 'libsass': this feature is not available
in your current Hugo version
```

本地下载标准版 Hugo 可以 100% 复现，同样的报错。

### 为什么之前一直"看起来正常"

因为仓库里误提交了 `resources/_gen/`——那是 Hugo 的**资源编译缓存**。缓存命中时，Hugo 直接复用上次编译好的 CSS，**根本不会去调 libsass**，所以构建"成功"了。

一旦缓存被清理（或被 CI 忽略），问题立刻暴露。所以这不像是某次改动引入的新问题，而是**一直潜伏、直到缓存失效才爆发**。

> **教训**：`resources/_gen/` 绝对不要进仓库。它会把"编译失败"伪装成"编译成功"，等缓存失效时炸得更突然。

## 2.4 解决方案：三级降级

核心思路：**不管构建机是什么版本、装没装 Dart Sass，都不要让构建失败。**

覆盖 `layouts/_partials/head/style.html`（项目根目录优先于主题）：

```go-html-template
{{- $sass := resources.Get "scss/style.scss" -}}
{{- $style := false -}}

{{- /* 1. libsass：extended 版 Hugo 内置，最快 */ -}}
{{- if not $style -}}
    {{- $cand := css.Sass (dict "transpiler" "libsass" "outputStyle" "compressed") $sass -}}
    {{- with try $cand.RelPermalink -}}
        {{- if not .Err -}}{{- $style = $cand -}}{{- end -}}
    {{- end -}}
{{- end -}}

{{- /* 2. dartsass：标准版 Hugo + 构建机上的 sass 命令 */ -}}
{{- if not $style -}}
    {{- $cand := css.Sass (dict "transpiler" "dartsass" "outputStyle" "compressed") $sass -}}
    {{- with try $cand.RelPermalink -}}
        {{- if not .Err -}}{{- $style = $cand -}}{{- end -}}
    {{- end -}}
{{- end -}}

{{- if $style -}}
    {{- $style = $style | resources.Fingerprint "sha256" -}}
    <link rel="stylesheet" href="{{ $style.RelPermalink }}">
{{- else -}}
    {{- /* 3. 兜底：读预编译好的 assets/scss/prebuilt.css */ -}}
    {{- $prebuilt := resources.Get "scss/prebuilt.css" -}}
    {{- if $prebuilt -}}
        {{- warnf "SCSS 无法编译，回退到 prebuilt.css" -}}
        {{- $prebuilt = $prebuilt | resources.Fingerprint "sha256" -}}
        <link rel="stylesheet" href="{{ $prebuilt.RelPermalink }}">
    {{- else -}}
        {{- errorf "SCSS 无法编译，且找不到 prebuilt.css" -}}
    {{- end -}}
{{- end -}}
```

### 关键坑：Hugo 的资源转换是「惰性的」

这一点必须单独讲，否则这段代码根本写不对。

`css.Sass` 调用本身**不会报错**，即使转译器不可用。真正的错误发生在你访问结果的时候——`.RelPermalink`、`.Content` 这类属性才会触发实际编译。

所以这样写是没用的：

```go-html-template
{{/* ✗ 错误：css.Sass 不抛错，try 抓不到 */}}
{{ with try (css.Sass (dict "transpiler" "libsass") $sass) }}
    {{ with .Err }}...{{ end }}
{{ end }}
```

必须把 `try` 包在**属性访问**上：

```go-html-template
{{/* ✓ 正确 */}}
{{ $cand := css.Sass (dict "transpiler" "libsass") $sass }}
{{ with try $cand.RelPermalink }}
    {{ if not .Err }}{{ $style = $cand }}{{ end }}
{{ end }}
```

### 三条路径的实测结果

每次构建前都先清空 `resources/_gen`，确保三条路径独立复现：

| 环境 | 转译器 | 产物文件名 | 大小 |
| --- | --- | --- | --- |
| extended 版 Hugo | libsass | `style.<hash>.css` | 60,456 B |
| 标准版 + Dart Sass | dartsass | `style.<hash>.css` | 59,744 B |
| 标准版 + 无 Sass | 兜底 | `prebuilt.<hash>.css` | 60,456 B |

> 前两种大小不同是正常的：libsass 和 dart-sass 的输出格式有细微差异。但两种都会用 `style.` 前缀，所以**只看文件名分不出转译器**，只能分出「编译成功」和「用了兜底」。

### 补充实验：缓存是怎么把失败藏起来的

为了确认「`resources/_gen` 会掩盖编译失败」这个判断，做了对照实验：

```powershell
# 步骤 1：用 extended 版构建一次，让 resources/_gen 写入编译缓存
Remove-Item "resources\_gen" -Recurse -Force
hugo --minify -d "$env:TEMP\m1"
#   → 产物 style.<hash>.css，无警告（正常编译）

# 步骤 2：紧接着用标准版 Hugo 构建（它没有 libsass）
& "$env:TEMP\hugo-std\hugo.exe" --minify -d "$env:TEMP\m2"
#   → 产物仍是 style.<hash>.css，依然没有任何警告
```

标准版明明编译不了 SCSS，却**静默成功**并输出了 `style.*`——因为它命中了步骤 1 写下的缓存，压根没调用转译器。

这就是为什么当初线上构建失败时，很难一眼看出问题：本地用 extended 版跑得通，缓存一提交，CI 上就"看起来也通"，直到某次缓存失效才集中爆发。

**结论**：`resources/_gen/` 必须 gitignore，它是"假成功"的源头。

### 当前线上走的是哪条路

产物文件前缀能区分「真实编译」和「兜底」：

| 文件名 | 含义 |
| --- | --- |
| `style.<hash>.css` | 真实编译成功（路径 1 libsass 或路径 2 dartsass） |
| `prebuilt.<hash>.css` | 触发了兜底快照（路径 3） |

当前线上是：

```
/scss/style.2a5ca823db389938089260c8a1cb5ce7fe528754bf741b64b86ade82b35b386f.css
```

前缀是 `style`，说明**编译真的成功了**，生产环境从未用过兜底。

进一步佐证：线上 CSS 是 **59,831 B**，与本地 dartsass 产物的 59,744 B 非常接近，而与 libsass 的 60,456 B 差距明显。

至于具体是 libsass 还是 dartsass，仅凭产物内容**区分不出来**——两种转译器对 `@font-face` 的引号处理实测完全一致（都输出 `font-family:"JetBrains Mono"`、`url("/fonts/...")`）。

但可以确定：Cloudflare 装的是标准版 Hugo，它没有 libsass，所以只能是 **dartsass（路径 2）** 在起作用——即构建环境里能调用到 `sass` 命令。

> 这是从「标准版不可能用 libsass」+「编译确实成功了」两条事实推出的结论，不是从构建日志直接确认的。如果哪天线上变成 `prebuilt.*` 前缀，说明构建环境的 `sass` 没了，届时按 2.5 切到 `bash bin/build.sh` 即可根治。

**文件名前缀就是判断依据**：

- `style.*` → 走了真实编译（路径 1 或 2），最理想
- `prebuilt.*` → 触发了兜底（路径 3），样式是快照

线上当前是：

```
/scss/style.2a5ca823...css   ← 前缀 style，说明实时编译成功
```

也就是说生产环境**没有**用到兜底。在标准版 Hugo 下，这只能说明构建机的 `PATH` 上有 `sass`（dart-sass），走了路径 2。

## 2.5 可选加固：`bin/build.sh`

虽然现在能用，但依赖"构建镜像恰好有 sass"这件事并不稳妥。`bin/build.sh` 把这件事变得明确：

```bash
bash bin/build.sh
```

它做的事：

1. 下载 **Dart Sass 1.80.4**（linux-x64）并加入 `PATH` → 让标准版 Hugo 能用 dartsass
2. 下载 **Hugo extended 0.168.0**（linux-amd64）并加入 `PATH` → 自带 libsass，更优
3. 最后执行 `hugo --minify`

两个下载都带重试，任一失败都只 WARN 不中断，保证脚本本身不会成为新的失败点。

**怎么启用**：Cloudflare 面板 → 构建配置 → 构建命令，把

```
hugo --minify
```

改成

```
bash bin/build.sh
```

> 不改也能跑（靠路径 2）。改了的收益是：环境变量 `HUGO_VERSION` 升级时行为和本地一致，且不依赖镜像里有没有 sass。

## 2.6 兜底样式 `prebuilt.css` 的维护

`assets/scss/prebuilt.css` 是一份「提前编译好的完整样式快照」，60KB。它在路径 3 被使用。

**必须记住的规则**：

> **改了 `custom.scss` 或主题 SCSS 的任何东西，就重新生成一次 `prebuilt.css`。**

否则万一哪天构建机没了 sass、又没有 extended，线上就会用上**旧样式**——而且构建是成功的，你不会收到任何报错，只是页面长得不对。

```bash
bash bin/update-prebuilt.sh
```

脚本会检查本地 Hugo 是否为 extended 版（不是就直接报错退出），编译到一个临时目录，把生成的 CSS 拷成 `assets/scss/prebuilt.css`。

## 2.7 缓存

线上响应带 `cf-cache-status: HIT`，也就是走了 Cloudflare 边缘缓存。正常情况部署完成后几十秒内会自动刷新。

如果改了代码、部署也成功了，但浏览器看到的还是旧样子：

1. 确认 `Deployments` 里最新一条是成功的、且提交号对得上
2. 对比 CSS 文件的哈希是否变了：`浏览器查看页面源码 → 搜 style.min.` 
   - 哈希变了 = 新版本已上线 = 本地缓存问题，`Ctrl+F5`
   - 哈希没变 = 部署没生效或构建失败

---

# 第三部分：样式是怎么实现的

所有自定义样式集中在 `assets/scss/custom.scss`（约 290 行，全中文注释）。它是在主题编译流程**之后**被 `@import` 进 `style.scss` 的，所以能覆盖主题的任何规则。

## 3.1 字体

原来用 `@import url('https://fonts.googleapis.com/...')` 引 Google Fonts，有两个问题：

- **外链慢**：国内基本连不上，代码块先渲染成 Consolas，等字体到位再跳一次（FOUC）
- **`@import` 位置限制**：Sass 会把它塞到打包结果最前面，反而容易触发层叠顺序问题

改成**自托管**：

```scss
@font-face {
    font-family: "JetBrains Mono";
    font-weight: 400;
    font-display: swap;
    src: url("/fonts/jetbrains-mono-latin-400.woff2") format("woff2");
}
```

字体文件在 `static/fonts/`，构建时直接复制到 `public/fonts/`。
另外覆盖了 `layouts/_partials/head/custom-font.html`，把主题原本加载 Lato 的 `<link>` 换成这两个字体的 `preload`——正文已经用系统中文黑体，Lato 根本用不到。

## 3.2 代码块：去掉底色 + 修复字号叠加

**去掉底色**：这是最初的需求，"代码框生硬的独立背景色"要和卡片融合。

```scss
.article-content pre,
.article-content code,
.article-content .highlight,
.article-content .highlight > .chroma,
.article-content pre.chroma,
.article-content .highlight table {
    background-color: transparent !important;
    border: none !important;
}
```

**修复字号叠加**（一个隐蔽的 bug）：原本的选择器组里同时写了 `.highlight`、`.chroma`、`pre.chroma`、`code`，而它们在 DOM 里是**互相嵌套**的：

```
.highlight > .chroma > table > td > pre.chroma > code
```

这组规则统一是 `font-size: 0.9em`，而 `em` 相对父元素计算，于是**层层相乘**。用浏览器 computed style 实测每一层的实际字号（视口 1440px）：

| 元素 | 计算后字号 |
| --- | --- |
| `.highlight` | 15.3px |
| `.highlight > .chroma` | 13.77px |
| `pre.chroma` | 11.9px |
| `code`（最终渲染） | **10.71px** |

也就是说，本来想设成 14.4px 的代码，实际只有 **10.7px**——这就是代码看起来特别小的原因。

正确做法是**只在一层定基准**，子孙全部 `1em` 继承：

```scss
.article-content .highlight {
    font-size: var(--code-font-size) !important;  /* 只在这里设 */
}

.article-content .highlight pre,
.article-content .highlight code,
.article-content .highlight .lnt,
.article-content .highlight td {   /* 注意要包含 td，行号在表格里 */
    font-size: 1em !important;
    line-height: inherit !important;
}
```

修复后实测，四层全部收敛到同一个值：

| 元素 | 改前 | 改后 |
| --- | --- | --- |
| `.highlight` | 15.3px | 14px |
| `.highlight > .chroma` | 13.77px | 14px |
| `pre.chroma` | 11.9px | 14px |
| `code`（最终渲染） | 10.71px | **14px** |

> **踩坑提醒**：这里必须把 `td` 也一起重置。代码块的行号表是 `<table><td><pre>` 结构，漏掉 `td` 的话，行号那列会再被正文表格规则（0.92em）缩一次，导致行号和代码对不齐。

**修复右侧溢出**：主题给 `.highlight` 加了负边距和 `width: 100% + 2×card-padding`，把它顶到卡片边缘。去掉底色后就不需要贴边了，必须复位，否则代码块比正文宽，右边被卡片裁掉：

```scss
.article-content .highlight {
    margin: 1.5rem 0 !important;
    width: auto !important;
    max-width: 100%;
    padding: 0 0 0 1rem !important;
    overflow-x: auto;              /* 长行在块内滚动，不撑破页面 */
    border-left: 3px solid rgba(255, 255, 255, 0.15) !important;
}
```

## 3.3 一个容易踩的 CSS 变量坑

```scss
/* ✗ 错误：整条声明会失效 */
:root {
    --code-font-family: "JetBrains Mono", Consolas, monospace !important;
}
```

`!important` 在自定义属性（CSS 变量）里是**无效的**。它会被原样写进变量值，导致 `--code-font-family` 这条声明整体失效，后续所有 `font-family: var(--code-font-family)` 全部 fallback。

变量里**不要**写 `!important`。

## 3.4 排版与留白

| 变量 | 值 | 说明 |
| --- | --- | --- |
| `--article-font-size` | 15.5px / 16px（≥768px） | 中文正文舒适区 |
| `--article-line-height` | 1.85 | |
| `--code-font-size` | 14px | 等宽字体字面偏宽，略小于正文 |
| `--container-padding` | 16 / 24 / 40px | 随屏幕放大 |

**页面宽度**：主题 `.container.compact` 在 1400px 视口下会吃满 1280px，两侧只剩 60px，卡片几乎顶到窗口边缘。按档位收窄：

```scss
.container.compact {
    @media (min-width: 768px)  { max-width: 780px; }
    @media (min-width: 1024px) { max-width: 1000px; }
    @media (min-width: 1280px) { max-width: 1120px; }
    @media (min-width: 1536px) { max-width: 1180px; }
}
```

效果（1440px 视口）：

| | 改前 | 改后 |
| --- | --- | --- |
| 容器 | 1280px | 1120px |
| 两侧留白 | 65px | 145px |
| 卡片 | 952px | 792px |

**标题层级**：主题没有给正文 h2 设定字号，用的是浏览器默认值 **24px**（1.5em × 16px 基字号）——恰好和文章大标题 `.article-title` 的 24px 撞车，标题和章节看不出主次。实测对照：

| 元素 | 改前 | 改后 |
| --- | --- | --- |
| 文章大标题 | 24px | 24px |
| 正文 h2 | 24px（撞车） | 20px |
| 正文 h3 | 18.72px | 17px |
| 正文 | 16px | 16px |

## 3.5 修复过的零碎问题

| 问题 | 原因 | 处理 |
| --- | --- | --- |
| 页面出现 5 条突兀横线 | `csp-bancs.md` 里残留 `---` | 删除 5 处，代码块后补空行 |
| 每篇底部有空白灰卡片 | 开启 disqus 但没配 `shortname` | `comments.enabled = false` |
| 日期显示 `October 16, 2026` | `languageCode` 已弃用；缺 `[languages]` 块 | 改用 `locale` + 声明 `zh` |
| 复制按钮手机点不到 | 主题只在 `:hover` 显示 | `@media (hover: none)` 常驻 |
| 表格字号规则误伤代码块 | `table` 选择器命中了行号表 `lntable` | 限定 `.article-content > table` |

---

# 第四部分：排查手册

## 构建失败

**第一步：看完整日志**。Cloudflare 的日志面板会滚动，错误常常被 WARN 挡住，点「下载日志」看全文。

**第二步：本地复现**。用和服务器同版本的**标准版** Hugo 构建：

```powershell
hugo --minify
```

如果本地 extended 版能过、服务器不行，八成是 `extended` 差异。

**第三步：清缓存再试**。

```powershell
Remove-Item "resources\_gen" -Recurse -Force
hugo --minify
```

## 页面样式不对

按这个顺序查：

1. **CSS 文件前缀是什么**
   - `style.*` → 编译成功
   - `prebuilt.*` → 用了快照，说明 `prebuilt.css` 过期了 → 跑 `bash bin/update-prebuilt.sh`
2. **`custom.scss` 有没有被编译进去**：搜产物 CSS 里有没有 `--code-font-size`
3. **是不是浏览器缓存**：`Ctrl+F5`

## 页面莫名存在（删了源码还在线）

旧构建产物残留在 `public/` 里。检查：

```powershell
git ls-files public        # 应该为空
```

非空说明 `public/` 又被提交了，执行 `git rm -r --cached public`。

## 部署成功但线上没变化

1. 确认 `Deployments` 最新一条的提交号 = 本地 `git rev-parse --short HEAD`
2. 对比页面源码里的 CSS 哈希有没有变
3. 等一两分钟（边缘缓存）

---

# 附录：环境自检

```powershell
hugo version                    # 需要 extended（本地）
git submodule status            # 主题是否就位
git ls-files public             # 应为空
Get-ChildItem static\fonts      # 两个 woff2
(Get-Item assets\scss\prebuilt.css).Length   # 应为 6 万字节左右
```

```bash
# Git Bash / WSL
hugo --minify                                              # 能构建
grep -c "extended" <(hugo version)                         # 本地应为 1
```
