#!/usr/bin/env bash
# QuantOKX 后端部署 —— Debian 12，Java 21 用 Temurin 直链压缩包（绕过 apt 密钥问题）
set -euo pipefail

SERVER_DIR="/opt/quantokx"
JDK_DIR="/opt/jdk21"
JAR_URL="https://github.com/at9870451-bit/ios-todo-app/releases/download/server-v1.0.0/quant-okx-server.jar"
JRE_URL="https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jre/hotspot/normal/eclipse?project=jdk"
SERVICE_NAME="quantokx"
PORT=8080
JAVA_BIN="$JDK_DIR/bin/java"

echo "▶ [1/7] 装 Java 21（Temurin 直链）"
if "$JAVA_BIN" -version 2>&1 | head -1 | grep -q '"21'; then
    echo "  已装：$("$JAVA_BIN" -version 2>&1 | head -1)"
else
    echo "  下载 JRE 压缩包（52MB）"
    curl -fSL -o /tmp/jre21.tar.gz "$JRE_URL"
    rm -rf "$JDK_DIR"
    mkdir -p /opt
    tar xzf /tmp/jre21.tar.gz -C /opt
    # 解出来是 jdk-21.x.x+x 目录，改名统一
    mv /opt/jdk-21.* "$JDK_DIR" 2>/dev/null || true
    ln -sf "$JAVA_BIN" /usr/local/bin/java
    rm -f /tmp/jre21.tar.gz
    echo "  装好：$("$JAVA_BIN" -version 2>&1 | head -1)"
fi

echo "▶ [2/7] 放 jar"
mkdir -p "$SERVER_DIR"
cd "$SERVER_DIR"
if [ -f app.jar ]; then
    echo "  已存在 app.jar，跳过"
else
    echo "  下载 jar（21MB）"
    curl -fSL -o app.jar "$JAR_URL"
fi
echo "  大小：$(du -h app.jar | cut -f1)"

echo "▶ [3/7] 访问令牌"
if [ -f auth.token ]; then
    TOKEN=$(cat auth.token)
    echo "  沿用已有令牌"
else
    TOKEN=$(openssl rand -hex 16)
    echo -n "$TOKEN" > auth.token
    chmod 600 auth.token
    echo "  已生成新令牌"
fi

echo "▶ [4/7] systemd 服务"
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=QuantOKX Trading Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${SERVER_DIR}
ExecStart=${JAVA_BIN} -Xmx512m -Xms128m -jar ${SERVER_DIR}/app.jar
Environment=QUANTOKX_AUTH_TOKEN=${TOKEN}
Restart=on-failure
RestartSec=5
StandardOutput=append:${SERVER_DIR}/app.log
StandardError=append:${SERVER_DIR}/app.log

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1

echo "▶ [5/7] 放行防火墙 8080"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q active; then
    ufw allow ${PORT}/tcp >/dev/null 2>&1 || true
    echo "  ufw 已放行"
else
    echo "  无 ufw（记得在宝塔「安全」放行 8080）"
fi

echo "▶ [6/7] 启动"
systemctl restart "$SERVICE_NAME"

echo "▶ [7/7] 等待就绪（最多 60 秒）"
OK=no
for i in $(seq 1 60); do
    if curl -s -m 2 "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
        echo "  ✅ 就绪（${i} 秒）"
        OK=yes
        break
    fi
    sleep 1
done

echo
echo "══════════════════════════════════════"
if [ "$OK" = yes ]; then
    curl -s -m 5 "http://127.0.0.1:${PORT}/api/health"; echo
    echo "✅ 后端启动成功"
else
    echo "✗ 健康检查失败，日志："
    tail -25 "$SERVER_DIR/app.log" 2>/dev/null || journalctl -u ${SERVICE_NAME} -n 25 --no-pager
    exit 1
fi
echo "══════════════════════════════════════"
echo
echo "★ iOS App「设置」页填："
echo "  地址：http://64.83.22.85:${PORT}"
echo "  令牌：${TOKEN}"
