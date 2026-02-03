#!/bin/bash
# ==============================================================================
# K3s 自动优化安装脚本 (weix2025/k3s-installer)
# Power by @weix2025 && OpenClaw
# ==============================================================================
set -e

# --- 1. 基础配置 ---
GITHUB_USER="weix2025"
GITHUB_REPO="k3s-installer"
BRANCH="main"

# --- 2. 脚本内置硬编码源 ---
declare -A DEFAULT_SOURCES=(
    ["docker"]="docker.m.daocloud.io,mirror.baidubce.com,docker.mirrors.sjtug.sjtu.edu.cn,docker.nju.edu.cn"
    ["quay"]="quay.m.daocloud.io,quay.1ms.run,quay.nju.edu.cn"
    ["gcr"]="gcr.m.daocloud.io,gcr.1ms.run,gcr.nju.edu.cn"
    ["k8s-gcr"]="k8s-gcr.m.daocloud.io,registry.lank8s.cn,k8s-gcr.nju.edu.cn"
    ["k8s"]="k8s.m.daocloud.io,registry.k8s.io,k8s.nju.edu.cn"
    ["ghcr"]="ghcr.m.daocloud.io,ghcr.1ms.run,ghcr.nju.edu.cn"
)

declare -A REG_MAP=( ["docker"]="docker.io" ["quay"]="quay.io" ["gcr"]="gcr.io" ["k8s-gcr"]="k8s.gcr.io" ["k8s"]="registry.k8s.io" ["ghcr"]="ghcr.io" )
PROXIES=("https://ghfast.top/" "https://hk.gh-proxy.org/" "https://gh-proxy.org/" "https://cdn.gh-proxy.org/")

# 日志颜色与辅助
log_info() { echo -e "\033[32m[✓]\033[0m $1"; }
log_warn() { echo -e "\033[33m[!]\033[0m $1"; }
log_error() { echo -e "\033[31m[✗]\033[0m $1"; }

# 临时目录清理
MIRROR_DIR="/tmp/k3s_mirrors_$(date +%s)"
TEMP_RESULT=$(mktemp)
trap "rm -rf $MIRROR_DIR $TEMP_RESULT" EXIT
mkdir -p "$MIRROR_DIR"

# ==============================================================================
# 步骤 1: 地理位置探测
# ==============================================================================
check_env_proxy() {
    log_info "正在检测网络环境与地理位置..."
    local country="Unknown"
    country=$(curl -s --connect-timeout 2 https://ipapi.co/country/ || echo "Unknown")
    country=$(echo "$country" | tr '[:lower:]' '[:upper:]')

    if [[ "$country" == "CN" || "$country" == "UNKNOWN" ]]; then
        log_warn "环境判定为国内，正在选择 GitHub 加速代理..."
        for p in "${PROXIES[@]}"; do
            if curl -I -s --connect-timeout 2 "${p}https://gh-proxy.org/https://github.com" > /dev/null; then
                GH_PROXY="$p"
                log_info "选用代理: $GH_PROXY"
                break
            fi
        done
    else
        log_info "环境判定为海外，直连下载"
        GH_PROXY=""
    fi
}

# ==============================================================================
# 步骤 2: 冗余 + 同步源
# ==============================================================================
load_and_merge_sources() {
    local BASE_URL="${GH_PROXY}https://gh-proxy.org/https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"

    for type in "${!REG_MAP[@]}"; do
        log_info "加载 ${type} 镜像列表..."
        local target_txt="$MIRROR_DIR/${type}.txt"
        local temp_remote="$MIRROR_DIR/${type}.remote"
        local remote_list=""

        # 1. 尝试主列表 (.txt)
        if curl -sLf --connect-timeout 3 "${BASE_URL}/${type}.txt" -o "$temp_remote" && [ -s "$temp_remote" ]; then
            remote_list=$(cat "$temp_remote")
            log_info "  - 远程同步成功"
        # 2. 尝试备份列表 (.txt.bak)
        elif curl -sLf --connect-timeout 3 "${BASE_URL}/${type}.txt.bak" -o "$temp_remote" && [ -s "$temp_remote" ]; then
            remote_list=$(cat "$temp_remote")
            log_warn "  - 主列表失败，已回滚至 7 日备份源 (.bak)"
        # 3. 最终兜底
        else
            log_warn "  - 远程无法连接，使用脚本内置兜底"
        fi

        # 合并硬编码源 + 远程源
        local local_list=$(echo "${DEFAULT_SOURCES[$type]}" | tr ',' '\n')
        echo -e "${local_list}\n${remote_list}" | sed 's/[[:space:]]//g' | grep -v '^$' | sort -u > "$target_txt"
    done
}

# ==============================================================================
# 步骤 3: 并发测速与生成配置
# ==============================================================================
check_speed_task() {
    local type=$1; local url=$2
    local time=$(curl -o /dev/null -s -I -w "%{time_starttransfer}" --connect-timeout 2 "https://$url/v2/")
    if [[ $? -eq 0 && "$time" != "0.000" ]]; then
        echo "$type $time $url" >> "$TEMP_RESULT"
    fi
}

optimize_and_config() {
    log_info "执行并行测速优选 (20 线程)..."
    for type in "${!REG_MAP[@]}"; do
        while read -r url; do
            [[ -z "$url" ]] && continue
            check_speed_task "$type" "$url" &
            [[ $(jobs -r | wc -l) -ge 20 ]] && wait -n
        done < "$MIRROR_DIR/${type}.txt"
    done
    wait

    log_info "生成 /etc/rancher/k3s/registries.yaml"
    mkdir -p /etc/rancher/k3s
    {
        echo "mirrors:"
        for type in "docker" "quay" "gcr" "ghcr" "k8s" "k8s-gcr"; do
            local key="${REG_MAP[$type]}"
            echo "  \"$key\":"
            echo "    endpoint:"
            local sorted=$(grep "^$type " "$TEMP_RESULT" | sort -n -k 2 | awk '{print $3}')
            if [[ -z "$sorted" ]]; then
                local fallback=$(echo "${DEFAULT_SOURCES[$type]}" | cut -d',' -f1)
                echo "      - \"https://$fallback\""
            else
                for s in $sorted; do
                    echo "      - \"https://$s\""
                done
            fi
        done
    } > /etc/rancher/k3s/registries.yaml
}

# ==============================================================================
# 步骤 4: 8C16G 优化安装
# ==============================================================================
install_k3s() {
    log_info "配置 8C16G 节点资源预留..."
    mkdir -p /etc/rancher/k3s
    cat > /etc/rancher/k3s/config.yaml << EOF
node-name: "$(hostname)"
node-ip: "$(hostname -I | awk '{print $1}')"
write-kubeconfig-mode: "644"
kubelet-arg:
  - "system-reserved=cpu=500m,memory=1Gi"
  - "kube-reserved=cpu=200m,memory=256Mi"
  - "eviction-hard=memory.available<500Mi,nodefs.available<10%"
  - "max-pods=110"
EOF

    log_info "拉取 K3s 安装脚本并执行..."
    export INSTALL_K3S_MIRROR="cn"
    curl -sfL "${GH_PROXY}https://gh-proxy.org/https://raw.githubusercontent.com/rancher/k3s/master/install.sh" | \
    INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -
}

# ==============================================================================
# 执行流程
# ==============================================================================
check_env_proxy
load_and_merge_sources
optimize_and_config
install_k3s

log_info "K3s 安装与镜像优选完成！"
kubectl get nodes
