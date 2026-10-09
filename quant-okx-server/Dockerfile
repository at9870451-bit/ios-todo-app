# QuantOKX 后端镜像（Java 21 JRE）
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# 以非 root 用户运行；/app/data 用于持久化 config.json
RUN addgroup -S quant && adduser -S -G quant quant && mkdir -p /app/data && chown -R quant:quant /app

# 构建产物固定为 target/quant-okx-server.jar（见 pom.xml 的 finalName）
COPY --chown=quant:quant target/quant-okx-server.jar /app/app.jar

USER quant

# JVM 参数可通过 -e JAVA_TOOL_OPTIONS="-Xmx256m" 传入（exec 形式 ENTRYPOINT 下 JAVA_TOOL_OPTIONS 由 JVM 自动读取）
ENV JAVA_TOOL_OPTIONS=""

EXPOSE 8080

ENTRYPOINT ["java","-jar","/app/app.jar"]
