#!/usr/bin/env bash
# QuantOKX 后端一键部署脚本
# 用法（在服务器上以 root 运行）：
#   curl -fsSL https://cdn.jsdelivr.net/gh/at9870451-bit/ios-todo-app@main/quant-okx-server/deploy.sh | bash
#
# 可选环境变量：
#   QUANTOKX_AUTH_TOKEN=xxx   自定义访问令牌（默认随机生成）
#   JAR_URL=...              自定义 jar 下载地址
set -euo pipefail

SERVER_DIR="/opt/quantokx"
JAR_URL="${JAR_URL:-https://github.com/at9870451-bit/ios-todo-app/releases/download/server-v1.0.0/quant-okx-server.jar}"
SERVICE_NAME="quantokx"
PORT=8080

c() { printf '\033[%sm' "$1"; }
say()  { echo "${c}32▶ $*${c}0"; }
warn() { echo "${c}33▶ $*${c}0" >&2; }
err()  { echo "${c}31✗ $*${c}0" >&2; }

say "QuantOKX 后端部署开始"

# ── 1. Java 21 ─────────────────────────────────────────────
if command -v java >/dev/null 2>&1 && java -version 2>&1 | head -1 | grep -q '"21'; then
    say "Java 21 已安装"
else
    say "安装 OpenJDK 21（首次约 1-2 分钟）"
    apt-get update -qq
    apt-get install -y openjdk-21-jre-headless >/dev/null
    say "Java 版本：$(java -version 2>&1 | head -1)"
fi

# ── 2. 目录 + jar ──────────────────────────────────────────
mkdir -p "$SERVER_DIR"
cd "$SERVER_DIR"

if [ -f app.jar ] && [ "${FORCE:-0}" != "1" ]; then
    say "已存在 app.jar，跳过下载（FORCE=1 可强制重下）"
else
    say "下载后端 jar（20MB，从 GitHub Release）"
    if command -v wget >/dev/null; then
        wget -q --show-progress -O app.jar "$JAR_URL" || wget -q -O app.jar "$JAR_URL"
    else
        curl -fSL -o app.jar "$JAR_URL"
    fi
fi
say "jar 大小：$(du -h app.jar | cut -f1)"

# ── 3. 令牌 ────────────────────────────────────────────────
if [ -f "$SERVER_DIR/auth.token" ]; then
    TOKEN=$(cat "$SERVER_DIR/auth.token")
    say "沿用已有访问令牌"
else
    TOKEN="${QUANTOKX_AUTH_TOKEN:-$(openssl rand -hex 16)}"
    echo -n "$TOKEN" > "$SERVER_DIR/auth.token"
    chmod 600 "$SERVER_DIR/auth.token"
fi

# ── 4. systemd 服务 ────────────────────────────────────────
say "配置 systemd 服务"
# 1G 内存机器限制堆 256M，避免和 MariaDB 抢内存
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=QuantOKX Trading Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${SERVER_DIR}
ExecStart=/usr/bin/java -Xmx256m -Xms128m -jar ${SERVER_DIR}/app.jar
Environment=QUANTOKX_AUTH_TOKEN=${TOKEN}
Environment=SPRING_PROFILES_ACTIVE=default
Restart=on-failure
RestartSec=5
StandardOutput=append:${SERVER_DIR}/app.log
StandardError=append:${SERVER_DIR}/app.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1

# ── 5. 防火墙 ──────────────────────────────────────────────
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp >/dev/null 2>&1 || true
    say "已放行 ${PORT}/tcp（如有 ufw）"
fi

# ── 6. 启动 + 等就绪 ───────────────────────────────────────
say "启动服务"
systemctl restart "$SERVICE_NAME"

say "等待端口 ${PORT} 就绪（最多 30 秒）"
for i in $(seq 1 30); do
    if ss -lnt 2>/dev/null | grep -q ":${PORT} " || \
       command -v curl >/dev/null 2>&1 && \
       curl -s -m 2 "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ── 7. 自检 ────────────────────────────────────────────────
echo
echo "${c}36══════════════════════════════════════════${c}0"
if curl -s -m 5 "http://127.0.0.1:${PORT}/api/health" | head -c 200; then
    echo
    say "✅ 后端已启动"
else
    err "健康检查失败，看日志：journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
    exit 1
fi
echo "${c}36══════════════════════════════════════════${c}0"
echo
echo "iOS App「设置」页填："
IPV6=$(ip -6 addr show scope global 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-f:]+' | head -1 || true)
HOST="${IPV6:-2404:8c80:85:8001::be}"
echo "  地址：http://[${HOST}]:${PORT}"
echo "  令牌：${TOKEN}"
echo
echo "管理命令："
echo "  看状态：systemctl status ${SERVICE_NAME}"
echo "  看日志：journalctl -u ${SERVICE_NAME} -f"
echo "  重启：  systemctl restart ${SERVICE_NAME}"
echo "  停止：  systemctl stop ${SERVICE_NAME}"
echo
warn "令牌已存 ${SERVER_DIR}/auth.token，妥善保管。"
