```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Komari Agent + Cloudflared
# 直接下载并运行，不安装、不注册 systemd
#
# 必需：
#   AGENT_ENDPOINT
#   AGENT_TOKEN
#   CLOUDFLARED_TUNNEL_TOKEN
#
# 可选：
#   AGENT_INTERVAL=3
#   AGENT_DISABLE_AUTO_UPDATE=false
#   AGENT_DISABLE_WEB_SSH=false
#   AGENT_IGNORE_UNSAFE_CERT=false
#
# ============================================================

WORK_DIR="$(mktemp -d)"

KOMARI_BIN="${WORK_DIR}/komari-agent"
CLOUDFLARED_BIN="${WORK_DIR}/cloudflared"

cleanup() {
    echo
    echo "[INFO] 正在停止服务..."

    if [[ -n "${KOMARI_PID:-}" ]] && kill -0 "${KOMARI_PID}" 2>/dev/null; then
        kill "${KOMARI_PID}" 2>/dev/null || true
    fi

    if [[ -n "${CLOUDFLARED_PID:-}" ]] && kill -0 "${CLOUDFLARED_PID}" 2>/dev/null; then
        kill "${CLOUDFLARED_PID}" 2>/dev/null || true
    fi

    rm -rf "${WORK_DIR}"

    echo "[INFO] 已清理临时文件"
}

trap cleanup EXIT INT TERM

log() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

die() {
    error "$*"
    exit 1
}

# ============================================================
# 检查依赖
# ============================================================

command -v curl >/dev/null 2>&1 \
    || die "缺少 curl"

command -v uname >/dev/null 2>&1 \
    || die "缺少 uname"

# ============================================================
# 检查环境变量
# ============================================================

: "${AGENT_ENDPOINT:?请设置 AGENT_ENDPOINT}"
: "${AGENT_TOKEN:?请设置 AGENT_TOKEN}"
: "${CLOUDFLARED_TUNNEL_TOKEN:?请设置 CLOUDFLARED_TUNNEL_TOKEN}"

AGENT_INTERVAL="${AGENT_INTERVAL:-3}"
AGENT_DISABLE_AUTO_UPDATE="${AGENT_DISABLE_AUTO_UPDATE:-false}"
AGENT_DISABLE_WEB_SSH="${AGENT_DISABLE_WEB_SSH:-false}"
AGENT_IGNORE_UNSAFE_CERT="${AGENT_IGNORE_UNSAFE_CERT:-false}"

# ============================================================
# 检测架构
# ============================================================

case "$(uname -m)" in
    x86_64|amd64)
        KOMARI_ARCH="amd64"
        CLOUDFLARED_ARCH="amd64"
        ;;

    aarch64|arm64)
        KOMARI_ARCH="arm64"
        CLOUDFLARED_ARCH="arm64"
        ;;

    armv7l|armv7)
        KOMARI_ARCH="arm"
        CLOUDFLARED_ARCH="arm"
        ;;

    i386|i686)
        KOMARI_ARCH="386"
        CLOUDFLARED_ARCH="386"
        ;;

    *)
        die "不支持的架构：$(uname -m)"
        ;;
esac

log "架构：$(uname -m)"
log "Komari 架构：${KOMARI_ARCH}"
log "Cloudflared 架构：${CLOUDFLARED_ARCH}"

# ============================================================
# 获取 Komari 最新版本
# ============================================================

log "获取 Komari 最新版本..."

KOMARI_TAG="$(
    curl -fsSL \
        "https://api.github.com/repos/komari-monitor/komari-agent/releases/latest" |
        grep -m1 '"tag_name":' |
        sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/'
)"

[[ -n "${KOMARI_TAG}" ]] \
    || die "无法获取 Komari 最新版本"

log "Komari 版本：${KOMARI_TAG}"

# ============================================================
# 获取 Cloudflared 最新版本
# ============================================================

log "获取 Cloudflared 最新版本..."

CLOUDFLARED_TAG="$(
    curl -fsSL \
        "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" |
        grep -m1 '"tag_name":' |
        sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/'
)"

[[ -n "${CLOUDFLARED_TAG}" ]] \
    || die "无法获取 Cloudflared 最新版本"

log "Cloudflared 版本：${CLOUDFLARED_TAG}"

# ============================================================
# 下载 Komari
# ============================================================

KOMARI_URL="https://github.com/komari-monitor/komari-agent/releases/download/${KOMARI_TAG}/komari-agent-linux-${KOMARI_ARCH}"

log "下载 Komari Agent..."

curl -fL \
    --retry 5 \
    --retry-delay 2 \
    --connect-timeout 15 \
    -o "${KOMARI_BIN}" \
    "${KOMARI_URL}" \
    || die "Komari Agent 下载失败"

chmod +x "${KOMARI_BIN}"

# ============================================================
# 下载 Cloudflared
# ============================================================

case "${CLOUDFLARED_ARCH}" in
    amd64)
        CLOUDFLARED_ASSET="cloudflared-linux-amd64"
        ;;

    arm64)
        CLOUDFLARED_ASSET="cloudflared-linux-arm64"
        ;;

    arm)
        CLOUDFLARED_ASSET="cloudflared-linux-arm"
        ;;

    386)
        CLOUDFLARED_ASSET="cloudflared-linux-386"
        ;;
esac

CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_TAG}/${CLOUDFLARED_ASSET}"

log "下载 Cloudflared..."

curl -fL \
    --retry 5 \
    --retry-delay 2 \
    --connect-timeout 15 \
    -o "${CLOUDFLARED_BIN}" \
    "${CLOUDFLARED_URL}" \
    || die "Cloudflared 下载失败"

chmod +x "${CLOUDFLARED_BIN}"

# ============================================================
# 显示配置
# ============================================================

echo
echo "============================================================"
echo " Komari Agent"
echo "============================================================"
echo "Endpoint : ${AGENT_ENDPOINT}"
echo "Interval : ${AGENT_INTERVAL}"
echo
echo "============================================================"
echo " Cloudflared"
echo "============================================================"
echo "Tunnel Token : 已设置"
echo
echo "============================================================"
echo

# ============================================================
# 启动 Komari
# ============================================================

log "启动 Komari Agent..."

export AGENT_ENDPOINT
export AGENT_TOKEN
export AGENT_INTERVAL
export AGENT_DISABLE_AUTO_UPDATE
export AGENT_DISABLE_WEB_SSH
export AGENT_IGNORE_UNSAFE_CERT

"${KOMARI_BIN}" &
KOMARI_PID=$!

log "Komari PID：${KOMARI_PID}"

# ============================================================
# 启动 Cloudflared
# ============================================================

log "启动 Cloudflared..."

"${CLOUDFLARED_BIN}" \
    tunnel \
    --no-autoupdate \
    run \
    --token "${CLOUDFLARED_TUNNEL_TOKEN}" &

CLOUDFLARED_PID=$!

log "Cloudflared PID：${CLOUDFLARED_PID}"

echo
echo "============================================================"
echo " 服务已启动"
echo "============================================================"
echo " Komari PID      : ${KOMARI_PID}"
echo " Cloudflared PID : ${CLOUDFLARED_PID}"
echo
echo " 按 Ctrl+C 停止两个服务"
echo "============================================================"
echo

# ============================================================
# 等待进程
# ============================================================

while true; do
    if ! kill -0 "${KOMARI_PID}" 2>/dev/null; then
        error "Komari Agent 已退出"
        exit 1
    fi

    if ! kill -0 "${CLOUDFLARED_PID}" 2>/dev/null; then
        error "Cloudflared 已退出"
        exit 1
    fi

    sleep 5
done
```
