#!/bin/bash
# =============================================================================
# Claude Code 安装脚本 - 专为 proot-distro Debian 设计
# 工具链：fnm → Node.js 24 → pnpm 10 + bun → Claude Code
#
# 使用方式：
#   proot-distro install debian
#   proot-distro login debian
#   bash install-claude-debian.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[·]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
step()  { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }
die()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

echo -e "\n${GREEN}━━━ Claude Code × proot-distro Debian ━━━${NC}"
echo -e "${GREEN}    fnm · Node 24 · pnpm 10 · bun · claude${NC}\n"

# ── 1. 修复 proot 基础环境 ────────────────────────────────────────────────────
step "修复 proot 基础环境"

mkdir -p /tmp && chmod 1777 /tmp

if [[ ! -s /etc/resolv.conf ]]; then
  printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf
  info "已写入 DNS 配置"
fi

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
ok "基础环境就绪"

# ── 2. 安装系统依赖 ───────────────────────────────────────────────────────────
step "安装系统依赖"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  curl ca-certificates git unzip ripgrep procps bash
ok "系统依赖就绪"

# ── 3. 安装 fnm ───────────────────────────────────────────────────────────────
step "安装 fnm (Fast Node Manager)"

export FNM_DIR="$HOME/.fnm"

if command -v fnm &>/dev/null; then
  ok "fnm 已安装: $(fnm --version)"
else
  info "下载并安装 fnm..."
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell
  ok "fnm 安装完成"
fi

# 让 fnm 在当前 shell 生效
export PATH="$FNM_DIR:$PATH"
eval "$(fnm env --use-on-cd --shell bash 2>/dev/null)"
ok "fnm $(fnm --version) 已激活"

# ── 4. 安装 Node.js 24 ────────────────────────────────────────────────────────
step "安装 Node.js 24 (via fnm)"

info "安装 Node.js 24..."
fnm install 24
fnm use 24
fnm default 24
ok "Node.js $(node --version) | npm $(npm --version)"

# ── 5. 配置 npm 全局目录 ──────────────────────────────────────────────────────
step "配置 npm 全局目录"

export NPM_CONFIG_PREFIX="$HOME/.npm-global"
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
ok "npm 全局目录: $HOME/.npm-global"

# ── 6. 安装 pnpm 10 ───────────────────────────────────────────────────────────
step "安装 pnpm 10"

npm install -g pnpm@10
ok "pnpm $(pnpm --version)"

export PNPM_HOME="$HOME/.local/share/pnpm"
mkdir -p "$PNPM_HOME"
export PATH="$PNPM_HOME:$PATH"
pnpm config set global-bin-dir "$PNPM_HOME"

# ── 7. 安装 bun ───────────────────────────────────────────────────────────────
step "安装 bun"

export BUN_INSTALL="$HOME/.bun"
if command -v bun &>/dev/null; then
  ok "bun 已安装: $(bun --version)"
else
  info "下载并安装 bun..."
  curl -fsSL https://bun.sh/install | bash
  export PATH="$BUN_INSTALL/bin:$PATH"
  ok "bun $(bun --version)"
fi

# ── 8. 安装 Claude Code ───────────────────────────────────────────────────────
step "安装 Claude Code"

info "通过 npm 全局安装 @anthropic-ai/claude-code..."
npm install -g @anthropic-ai/claude-code
ok "Claude Code 安装完成"

# ── 9. 写入 ~/.bashrc ─────────────────────────────────────────────────────────
step "持久化环境变量到 ~/.bashrc"

BASHRC="$HOME/.bashrc"

if ! grep -q "# >>> fnm + claude-code <<<" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" << 'RCBLOCK'

# >>> fnm + claude-code <<<
# fnm
export FNM_DIR="$HOME/.fnm"
export PATH="$FNM_DIR:$PATH"
eval "$(fnm env --use-on-cd --shell bash 2>/dev/null)"

# npm global
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
# <<< fnm + claude-code <<<
RCBLOCK
  ok "已更新 ~/.bashrc"
else
  info "~/.bashrc 已包含配置，跳过"
fi

# ── 10. 验证全部工具 ──────────────────────────────────────────────────────────
step "验证安装结果"

check() {
  local name="$1" cmd="$2"
  local ver
  if ver=$($cmd 2>/dev/null); then
    echo -e "  ${GREEN}✓${NC} ${name}: ${CYAN}${ver}${NC}"
  else
    echo -e "  ${YELLOW}?${NC} ${name}: 需要 source ~/.bashrc 后验证"
  fi
}

check "fnm"      "fnm --version"
check "Node.js"  "node --version"
check "npm"      "npm --version"
check "pnpm"     "pnpm --version"
check "bun"      "bun --version"
check "claude"   "claude --version"

# ── 完成 ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  全部安装完成！                             ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}source ~/.bashrc${NC}                    # 刷新环境变量"
echo -e "  ${CYAN}export ANTHROPIC_API_KEY='sk-ant-...'${NC}  # 设置 API Key"
echo -e "  ${CYAN}claude${NC}                              # 启动 Claude Code"
echo ""
echo -e "  常用 fnm 命令："
echo -e "    ${CYAN}fnm list${NC}          # 查看已装版本"
echo -e "    ${CYAN}fnm install 22${NC}    # 安装其他版本"
echo -e "    ${CYAN}fnm use 22${NC}        # 切换版本"
echo ""
