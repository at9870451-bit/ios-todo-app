# QuantOKX Server

OKX 加密货币自动交易引擎后端（Spring Boot 3 / Java 21），配套 iOS App「QuantOKX」的控制台接口。

- 策略引擎与 iOS 端（`quant-okx-ios/QuantOKX/Sources`）逐行对照移植：网格 / 均线交叉 / RSI / 通道突破 + 止盈止损风控，两端行为一致
- 接口严格实现 `quant-okx-API.md` 契约：统一信封 `{"code":0,"msg":"ok","data":...}`，字段名不可改
- 无需数据库：配置与日志存内存 + `./data/config.json` 持久化（权限 600）
- HTTP 客户端使用 JDK 自带 `java.net.http.HttpClient`，不引入 OkHttp/Feign
- 默认模拟盘（`demoTrading=true`），密钥全程脱敏

---

## 1. 目录结构

```
quant-okx-server/
├── pom.xml
├── README.md
├── Dockerfile
├── .gitignore
├── .github/workflows/build.yml        # CI：构建 + 上传 jar，打 v* tag 时创建 Release
└── src/main/
    ├── java/com/quantokx/
    │   ├── QuantOkxApplication.java   # 启动入口（@EnableScheduling）+ 启动横幅
    │   ├── config/                    # QuantOkxProperties、WebConfig（CORS+拦截器注册）、SecretScrubber
    │   ├── model/                     # 领域模型 + DTO（AppConfig、Signal、Ticker、Candle、ApiModels…）
    │   ├── okx/                       # OkxClient（签名+HTTP）、OkxSigner、OkxException
    │   ├── indicator/                 # Indicator：SMA / RSI(Wilder) / std
    │   ├── strategy/                  # StrategyContext、StrategyEngine（4 策略 + 风控检查 + AI 摘要）
    │   ├── ai/                        # AiClient（OpenAI 兼容，宽松 JSON 解析）
    │   ├── engine/                    # TradingEngine（@Scheduled）、RiskManager、TradeLogStore
    │   ├── store/                     # ConfigStore（./data/config.json 持久化、热更新、掩码）
    │   └── web/                       # ApiController、AuthInterceptor、ApiResponse、GlobalExceptionHandler
    └── resources/application.yml
```

---

## 2. 本地运行

前置要求：JDK 21、Maven 3.9+。

```bash
# 1) 构建
mvn -B package -DskipTests
# 产物：target/quant-okx-server.jar

# 2) 运行（默认 8080 端口，模拟盘）
java -jar target/quant-okx-server.jar

# 或开发模式直接跑
mvn spring-boot:run
```

启动后会打印醒目的横幅，明确当前是「模拟盘」还是「实盘」：

```
========================================================
QuantOKX 后端已启动  v1.0.0  端口 8080
交易模式：模拟盘（demoTrading=true，签名请求带 x-simulated-trading:1）—— 安全
OKX 凭据：未配置（key 未配置；来源：环境变量优先，其次 ./data/config.json）
默认策略：maCross  交易对：BTC-USDT-SWAP  周期：1m  轮询：15s
鉴权令牌仍是默认值 changeme，请修改 application.yml 的 quantokx.auth-token（或设置环境变量 QUANT_OKX_AUTH_TOKEN）
========================================================
```

### 冒烟测试

```bash
# 无需鉴权
curl -s http://localhost:8080/api/health

# 其余接口都要带 X-Auth-Token
curl -s -H 'X-Auth-Token: changeme' http://localhost:8080/api/status
curl -s -H 'X-Auth-Token: changeme' http://localhost:8080/api/config
curl -s -H 'X-Auth-Token: changeme' 'http://localhost:8080/api/market/ticker?instId=BTC-USDT-SWAP'
curl -s -H 'X-Auth-Token: changeme' 'http://localhost:8080/api/market/candles?instId=BTC-USDT-SWAP&bar=1m&limit=5'
curl -s -H 'X-Auth-Token: changeme' -X POST http://localhost:8080/api/config/test
```

---

## 3. Docker 运行

```bash
# 构建镜像（先 mvn package，Dockerfile 直接拷贝 target/quant-okx-server.jar）
mvn -B package -DskipTests
docker build -t quant-okx-server:1.0.0 .

# 运行（挂载 ./data 持久化配置；JAVA_TOOL_OPTIONS 用于限制内存）
docker run -d --name quant-okx \
  -p 8080:8080 \
  -v "$(pwd)/data:/app/data" \
  -e QUANT_OKX_AUTH_TOKEN='换成你的强令牌' \
  -e OKX_API_KEY='xxx' -e OKX_API_SECRET='yyy' -e OKX_PASSPHRASE='zzz' \
  -e JAVA_TOOL_OPTIONS='-Xmx256m' \
  quant-okx-server:1.0.0
```

> 镜像以非 root 用户 `quant` 运行；如果挂载的 `data` 目录不可写（容器日志报 `配置持久化失败`），
> 在宿主机执行 `sudo chown -R 1000:1000 ./data` 或改用环境变量提供密钥。

---

## 4. 部署到服务器（systemd）

以 Ubuntu/Debian、部署到 `/opt/quant-okx` 为例：

```bash
sudo adduser --system --group --no-create-home quantokx
sudo mkdir -p /opt/quant-okx
sudo cp target/quant-okx-server.jar /opt/quant-okx/app.jar
sudo mkdir -p /opt/quant-okx/data
sudo chown -R quantokx:quantokx /opt/quant-okx
```

`/etc/systemd/system/quant-okx.service`：

```ini
[Unit]
Description=QuantOKX trading engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=quantokx
WorkingDirectory=/opt/quant-okx
# 密钥放在 EnvironmentFile 里，文件权限 chmod 600，避免出现在 ps/日志
EnvironmentFile=/opt/quant-okx/quant-okx.env
ExecStart=/usr/bin/java -Xmx256m -jar /opt/quant-okx/app.jar
SuccessExitStatus=143
Restart=on-failure
RestartSec=5
# 最小权限加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=/opt/quant-okx/data

[Install]
WantedBy=multi-user.target
```

`/opt/quant-okx/quant-okx.env`（**权限务必 600**）：

```bash
QUANT_OKX_AUTH_TOKEN=换成你的强令牌
OKX_API_KEY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
OKX_API_SECRET=YYYYYYYYYYYYYYYYYYYYYYYYYYYY
OKX_PASSPHRASE=你的Passphrase
```

```bash
sudo chmod 600 /opt/quant-okx/quant-okx.env
sudo systemctl daemon-reload
sudo systemctl enable --now quant-okx
sudo systemctl status quant-okx
journalctl -u quant-okx -f
```

> 提示：当前是 iSH 沙箱、JetBrains 之类的环境时 JVM 可能无法启动（`getcpu(2) system call not supported`），
> 生产部署请使用正常 Linux 服务器；iOS 上也可以直接跑在 iSH 之外（比如家里的树莓派/NAS 容器）。

---

## 5. 环境变量

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `QUANT_OKX_AUTH_TOKEN` | 覆盖 `quantokx.auth-token`（前端 `X-Auth-Token` 鉴权令牌） | `changeme` |
| `OKX_API_KEY` | OKX API Key，**优先级高于 `./data/config.json`** | 空 |
| `OKX_API_SECRET` | OKX API Secret，同上 | 空 |
| `OKX_PASSPHRASE` | OKX API Passphrase，同上 | 空 |
| `JAVA_TOOL_OPTIONS` | JVM 参数（exec 形式 ENTRYPOINT 下由 JVM 自动读取） | 空 |

> 密钥读取优先级：**环境变量 > `./data/config.json`**（`PUT /api/config` 写入，权限 600）。
> 环境变量一旦设置，接口写入的密钥不会生效（但仍然会被持久化，便于切回）。
> 任何日志、异常消息、接口返回都不含密钥明文（`SecretScrubber` 统一脱敏）。

---

## 6. 配置 OKX API Key

方式一（推荐，App 内操作）：iOS App「设置」页填入 API Key / Secret / Passphrase，
点「保存」即调用 `PUT /api/config`；点「测试连接」调用 `POST /api/config/test`。

方式二（curl）：

```bash
curl -s -X PUT http://localhost:8080/api/config \
  -H 'X-Auth-Token: changeme' -H 'Content-Type: application/json' \
  -d '{"okxApiKey":"KEY","okxApiSecret":"SECRET","okxPassphrase":"PASS"}'
```

方式三（环境变量，见上一节）。

OKX 侧权限建议：
- 只勾选「交易」（Trade）权限，**不要**勾选「提币」（Withdraw）；
- 绑定服务器 IP 白名单；
- 先用模拟盘（demo trading）生成的 key 练手。

---

## 7. 模拟盘 / 实盘

- 默认 `demoTrading: true` —— 所有签名请求自动带 `x-simulated-trading: 1`，使用 OKX 模拟盘账户；
- 切换实盘：`PUT /api/config` 传 `{"demoTrading": false}`，或在 App 里关闭「模拟盘」开关；
- 切换后**下一轮轮询立即生效**（配置热更新），无需重启；
- 启动横幅与每轮轮询都会体现当前模式（实盘模式打印 `！！！实盘！！！` 警告）；
- 强烈建议：实盘前先把 `tradeSizeUSDT` / `maxPositionUSDT` 调小，确认行为符合预期。

---

## 8. 接口一览（契约 quant-okx-API.md）

除 `GET /api/health` 外都要求请求头 `X-Auth-Token: <token>`；
所有响应统一信封 `{"code":0,"msg":"ok","data":...}`。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/health` | 健康检查（免鉴权）：status/version/serverTime/javaVersion |
| GET | `/api/status` | 引擎状态：running/ticker/positions/lastSignal/lastAIReply 等 14 个字段 |
| POST | `/api/engine/start` | 启动引擎（缺密钥不启动，原因在 status.errorMessage） |
| POST | `/api/engine/stop` | 停止引擎 |
| GET | `/api/config` | 配置视图（密钥仅掩码 + okxConfigured/aiKeyConfigured） |
| PUT | `/api/config` | 部分更新（密钥 null=不改、""=清空；其余 null=不改），立即生效 |
| POST | `/api/config/test` | 测试 OKX 连通性（业务失败仍 code=0，用 ok/message 表达） |
| GET | `/api/market/ticker?instId=` | 行情（含 changePct） |
| GET | `/api/market/candles?instId=&bar=1m&limit=120` | K 线，**旧 → 新**排序 |
| GET | `/api/positions` | 非零持仓（数值保持 OKX 原始字符串） |
| GET | `/api/orders?instId=` | 未成交委托 |
| GET | `/api/logs?limit=200` | 交易日志（最新在前，最多 300 条） |
| DELETE | `/api/logs` | 清空日志，返回 `{cleared:N}` |
| POST | `/api/trade/close-all` | 一键全平，返回 `{closed:N,message:"已平仓 N 个"}` |
| POST | `/api/trade/order` | 手动下单（过 RiskManager），返回 `{ordId,success,message}` |
| GET | `/api/strategies` | 策略列表（grid/maCross/rsi/breakout/ai） |

错误约定：
- 鉴权失败 → **HTTP 401** + 信封 `{"code":401,...}`；
- 参数/业务错误 → HTTP 200 + `code=400`（msg 可直接展示）；未预期异常 → `code=500`；
- 前端统一按 `code != 0` 判断失败即可。

---

## 9. 交易引擎行为（与 iOS 端一致）

每轮顺序严格为：

1. 拉 `ticker` + `candles(120根, 配置的 bar)`
2. 拉 `positions(instType 按交易对) + balance`（失败不中断本轮，与 iOS 的 `try?` 一致）
3. **风控优先**：有持仓先按均价算收益率，触发止盈/止损直接平仓，本轮不再看策略
4. 策略决策：`ai` 策略走 `AiClient`（异步 + 超时保护），其余走 `StrategyEngine`
5. 下单前过 `RiskManager`：最大持仓上限、每小时下单次数（滑窗）、单笔金额
6. 日志 + 更新状态（`/api/status` 可实时观察）

策略阈值（两端一致）：MA 7/25，RSI 14（30/70），突破 20 根，网格区间 ±3%；
止盈止损按配置（默认 4% / 2%）。

### 配置热更新

`PUT /api/config` 后写入 `AtomicReference` 快照并落盘，引擎每轮读取最新快照 —— 下一轮立即生效。

> 实现说明：`@Scheduled(fixedDelayString = "#{@configStore.pollMillis}")` 的 SpEL 在注册时只会解析一次，
> 所以 `pollMillis` 固定返回 1 秒「心跳」，引擎每轮再按**当前** `pollSeconds` 判断是否真的执行，
> 从而实现轮询间隔可热更新（`pollSeconds` 会收敛到 [5, 3600]）。

---

## 10. 安全清单

- `GET /api/config` 永不返回密钥明文，只返回 `前4****后4` 掩码 + 是否已配置；
- 若前端把掩码原样回传（值里含 `****`），后端视为「不修改」，不会把掩码存成密钥；
- `./data/config.json` 写入后 chmod 600（POSIX 文件系统）；日志/异常/接口消息统一经 `SecretScrubber` 脱敏；
- 鉴权令牌默认为 `changeme`，启动时若仍是默认值会打印警告，**上线前务必修改**（`QUANT_OKX_AUTH_TOKEN`）；
- 默认模拟盘；实盘需显式切换。

---

## 11. 移植时与 Swift 参考实现的有意差异（人工复核点）

> 说明：以下差异来自「Java 侧逐行移植 Swift 策略源码」阶段；iOS 工程当前已改为纯控制台（交易逻辑不再内置），Java 引擎是唯一的交易实现。

| # | 位置 | iOS 行为 | 本后端行为 | 原因 |
| --- | --- | --- | --- | --- |
| 1 | 持仓名义价值 | `|pos| * price`（忽略合约面值） | `|pos| * ctVal * price`（现货 `|pos| * price`） | iOS 公式对 BTC-USDT-SWAP（ctVal=0.01）会高估 100 倍，导致几乎无法开仓；改为真实名义价值 |
| 2 | 拉持仓的 instType | 固定 `SWAP` | 按交易对推导（`-SWAP`→SWAP，否则 SPOT） | 现货交易时 iOS 会读不到持仓 |
| 3 | 一键全平范围 | 仅当前交易对 | 全部非零 SWAP 持仓 | 「close-all」语义；如需只平当前交易对可改 `TradingEngine.closeAll()` |
| 4 | 全平日志 action | `平仓` | `平多`/`平空` | 契约的 action 取值集合里没有 `平仓` |
| 5 | `status.positions` | 数组（可为空） | 数组（空数组，不为 null） | 契约注明「可为 null」，空数组对前端更安全 |
| 6 | 下单数量格式化 | `%.4f` / `%.8f` | 12 位有效数字去尾零（如 `0.1`、`3`） | 避免 `3.0000000000000004` / 科学计数法 |
| 7 | 网格策略 `gridLevels` | 声明未使用 | 声明未使用（保留同名参数） | 保持两端参数结构一致 |
| 8 | `riskCheck` 的 `uplRatioPct` | 声明未使用 | 声明未使用 | 同上 |

---

## 12. 构建 / CI

```bash
mvn -B package -DskipTests        # 产出 target/quant-okx-server.jar
mvn -B package                    # 跑测试（仓库里暂无测试类，等价于上面）
```

GitHub Actions（`.github/workflows/build.yml`）：`ubuntu-latest` + `setup-java` 21 + `mvn -B package -DskipTests`，
把 `target/quant-okx-server.jar` 上传为 artifact；推送 `v*` tag 时自动创建 Release 并附上 jar。

```bash
git tag v1.0.0 && git push origin v1.0.0   # 触发 Release
```

---

## 13. 策略移植对照（Swift 参考实现 <-> Java）

> 对照基准是移植时的 iOS 源码（`quant-okx-ios/QuantOKX/Sources/{Strategy,Models,Networking,Engine}`）；该工程随后被改造为纯控制台 App，上述 Swift 文件已不在工程内。

| 逻辑 | iOS 文件 | Java 文件 |
| --- | --- | --- |
| SMA / RSI(Wilder) / std | `Models/Models.swift` → `Indicator` | `indicator/Indicator.java` |
| 网格 / 均线交叉 / RSI / 通道突破 / 止盈止损 / AI 摘要 | `Strategy/StrategyEngine.swift` | `strategy/StrategyEngine.java`（阈值与文案逐条对照） |
| OKX V5 签名 + 接口路径 + sizeFor | `Networking/OKXClient.swift` | `okx/OkxSigner.java` + `okx/OkxClient.java` |
| AI 决策（宽松解析 + 置信度降级） | `Networking/AIClient.swift` | `ai/AiClient.java` |
| 轮询主循环 / 风控优先级 / 频率限制 / 日志 | `Engine/TradingEngine.swift` | `engine/TradingEngine.java` + `RiskManager` + `TradeLogStore` |

---

## 14. 联调验收清单（对着 iOS App 逐项过）

1. `GET /api/health` 通 → App「设置」页显示「后台在线 · v1.0.0 · Java 21」；
2. `PUT /api/config` 改交易对 / 策略 / 参数 → App「策略与参数」页保存后刷新一致；
3. `POST /api/config/test` → App 显示「✅ 连接正常 · 现价 … · 余额 …」（模拟盘时为模拟账户余额）；
4. `POST /api/engine/start` → Dashboard 变「停止自动交易」，tickCount 递增，uptime 增长；
5. 日志页能看到 START / 预览策略的「观望」类记录（hold 不写日志，触发条件下才有开/平仓记录）；
6. `POST /api/trade/close-all` → 有持仓时返回「已平仓 N 个」；
7. `DELETE /api/logs` → 「已清空 N 条日志」；
8. 401 场景：App 令牌故意填错 → 提示「鉴权失败，请检查「设置」里的访问令牌」。

---

## 15. 常见问题

**Q：为什么 PUT /api/config 改 pollSeconds 后要等一会才变？**
A：调度器每 1 秒醒一次，按当前 `pollSeconds` 判断是否该跑下一轮；最大滞后约 1 秒。

**Q：为什么日志里看不到「hold」？**
A：与 iOS 一致：只有风控触发、下单、跳过、错误等才会写日志，观望不写。

**Q：`./data/config.json` 里存了密钥，安全吗？**
A：文件权限 600（仅属主可读），且接口只返回掩码；更高安全等级请用环境变量注入密钥（env 优先，config.json 里的旧值不会生效）。

**Q：换到实盘要注意什么？**
A：① 关闭 OKX API Key 的「提币」权限；② 先小额（`tradeSizeUSDT`、`maxPositionUSDT` 调小）；③ 留意启动日志的「！！！实盘！！！」提示；④ 先观察 `GET /api/status` 的 `lastSignal` / `lastAIReply` 是否符合预期。

**Q：为什么 Java 端不用 Lombok / OkHttp / 数据库？**
A：按需求「依赖尽量少」；HTTP 用 JDK 自带 `java.net.http.HttpClient`，配置和日志用内存 + 单个 JSON 文件足够。
