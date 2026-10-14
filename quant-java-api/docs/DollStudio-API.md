# Doll Studio 3D — API 接口文档

> Amore App「玩偶」Tab · Q 版盲盒换装工作室
> iOS：Swift + SwiftUI + RealityKit（程序化 3D 玩偶，真实网格换装）
> 后端：Java 21 + Spring Boot 3.3.5 + MySQL 8（集成于 quant-java-api，v2.1.0）

---

## 1. 概览

| 端点组 | 前缀 | 认证 | 用途 |
|---|---|---|---|
| App 接口 | `/api/doll/**` | iOS 会话（QBSESSID Cookie + CSRF） | 目录 / 穿搭 CRUD / AI 推荐 |
| 管理台接口 | `/api/console/doll/**` | JWT Bearer + `doll:manage` 权限 | 款式/分类管理、模型上传、记录与日志 |

统一响应包装：`{"code":0,"message":"success","data":...}`（code≠0 为业务错误）。

**3D 模型说明**：App 内置 32 款程序化 3D 网格（发型 6 / 上衣 6 / 下装 4 / 围巾 2 / 帽子 4 / 鞋 4 / 配饰 6），
款式键（style）与后端 `DollSvc.STYLES` 严格一致。管理台可为款式上传自定义 USDZ/GLB 模型
（存 `data/doll-models/`，经 `/doll-assets/**` 静态下发），App 加载失败时自动回退程序化几何。

**AI 密钥安全**：AI 穿搭推荐使用服务端保存的 `ai_configs`（App「对话」页配置的那份，mode=chat 优先），
密钥永不下发客户端；每次调用写入 `doll_ai_logs` 审计。

---

## 2. App 接口（/api/doll/**）

### 2.1 GET /api/doll/catalog — 服装目录

响应 `data`：

```json
{
  "categories": [
    {"code": "hair", "name": "发型", "sort": 1},
    {"code": "top", "name": "上衣", "sort": 2},
    {"code": "bottom", "name": "下装", "sort": 3},
    {"code": "scarf", "name": "围巾", "sort": 4},
    {"code": "hat", "name": "帽子", "sort": 5},
    {"code": "shoes", "name": "鞋子", "sort": 6},
    {"code": "accessory", "name": "配饰", "sort": 7}
  ],
  "items": [
    {"id": 1, "category": "hair", "name": "清爽短发", "style": "short", "color": "#3B2B20",
     "premium": false, "model_url": null, "model_scale": 1.0, "model_offset_y": 0.0}
  ]
}
```

- 仅返回 `enabled=1` 的条目；App 网络失败时使用内置同款目录兜底。

### 2.2 GET /api/doll/outfits — 我的穿搭列表

响应 `data`：数组（最多 100 条，按更新时间倒序）

```json
[
  {"id": 12, "name": "海边度假", "gender": "female", "skin": "#F6D7BE",
   "state": "{\"gender\":\"female\",\"skin\":\"#F6D7BE\",\"items\":{\"top\":{\"style\":\"tee\",\"color\":\"#32ADE6\"}}}",
   "favorite": true, "created_at": "2026-10-15 10:00:00", "updated_at": "2026-10-15 10:30:00"}
]
```

`state` 为完整搭配 JSON 字符串（结构见 2.4）。

### 2.3 POST /api/doll/outfits — 保存穿搭

请求体：

```json
{"name": "海边度假", "gender": "female", "skin": "#F6D7BE", "state": "{\"gender\":...}"}
```

| 字段 | 约束 |
|---|---|
| name | ≤24 字，空则「未命名搭配」 |
| gender | `male` / `female` / `neutral` |
| skin | `#RRGGBB` |
| state | JSON 字符串 ≤8000 字符 |

限额：每用户 60 套，超出返回 422 `LIMIT_REACHED`。
响应 `data`：`{"id": 12}`

### 2.4 POST /api/doll/outfits/delete — 删除穿搭

```json
{"id": 12}
```

### 2.5 POST /api/doll/outfits/favorite — 收藏 / 取消收藏

```json
{"id": 12, "favorite": true}
```

### 2.6 POST /api/doll/ai/recommend — AI 穿搭推荐

请求体：

```json
{"gender": "female", "prompt": "夏天海边度假，清爽一点的蓝色系"}
```

响应 `data`（已通过服务端校验，款式必然合法）：

```json
{
  "items": {
    "top":    {"style": "tee",    "color": "#32ADE6", "item_id": 7, "name": "经典T恤"},
    "bottom": {"style": "skirt",  "color": "#FFFFFF", "item_id": 15, "name": "百褶短裙"},
    "hat":    {"style": "bucket", "color": "#E8E2D4", "item_id": 21, "name": "渔夫帽"},
    "shoes":  {"style": "sandals","color": "#C9A06B", "item_id": 26, "name": "凉鞋"}
  },
  "reason": "清爽蓝白配，海边度假刚刚好"
}
```

错误码：

| code | 场景 |
|---|---|
| `INVALID_PARAM` | prompt 为空 |
| `RATE_LIMIT` | 当日成功推荐超 30 次 |
| `AI_NO_CONFIG` | 服务端无可用 AI 配置 |
| `AI_PARSE` | AI 返回无法解析（可重试） |
| `AI_ERROR` | AI 接口调用失败（透出原始信息） |

搭配状态（state）结构：

```json
{
  "gender": "neutral",
  "skin": "#F6D7BE",
  "items": {
    "hair":      {"style": "short", "color": "#3B2B20"},
    "top":       {"style": "tee", "color": "#5B7FD4"},
    "bottom":    {"style": "shorts", "color": "#3E5C8A"},
    "scarf":     {"style": "scarf", "color": "#D9433B"},
    "hat":       {"style": "beanie", "color": "#D9433B"},
    "shoes":     {"style": "sneakers", "color": "#FFFFFF"},
    "accessory": {"style": "glasses", "color": "#2C2C2E"}
  }
}
```

---

## 3. 管理台接口（/api/console/doll/**，需 `doll:manage` 权限）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/meta` | 概览统计 + 全部款式键清单 |
| GET | `/categories` | 分类列表（含款式数） |
| PUT | `/categories/{id}` | 改名 / 排序 / 启停（code 与 App 构建器绑定，不可增删） |
| GET | `/items?page&size&category&keyword` | 款式分页列表 |
| POST | `/items` | 新增款式（校验分类/款式键/颜色） |
| PUT | `/items/{id}` | 更新款式 |
| DELETE | `/items/{id}` | 删除款式 |
| POST | `/upload` | 上传 3D 模型（multipart `file`，.usdz/.glb/.gltf/.reality ≤30MB）→ `{url}` |
| GET | `/outfits?page&size&keyword` | 全部用户穿搭记录（含 username） |
| DELETE | `/outfits/{id}` | 删除穿搭记录 |
| GET | `/ai-logs?page&size&status` | AI 调用日志分页 |
| GET | `/ai-logs/{id}` | 日志详情（含 AI 原始返回） |
| GET | `/ai-configs?page&size` | 用户 AI 配置列表（密钥掩码 `****abcd`） |

静态资源：`GET /doll-assets/{file}` — 上传的 3D 模型文件（无需认证）。

---

## 4. 数据库表（MySQL 8，SchemaBoot 启动自动建表 + 种子）

| 表 | 用途 |
|---|---|
| `doll_categories` | 服装分类（7 类固定 code） |
| `doll_items` | 服饰款式（category/style/color/premium/sort/enabled/model_url/model_scale/model_offset_y） |
| `doll_outfits` | 用户穿搭记录（user_id/name/gender/skin/state JSON/favorite） |
| `doll_ai_logs` | AI 推荐调用日志（prompt/result/status/duration_ms） |

种子数据：7 分类 + 32 款式（与 App 内置目录一致）。独立建表 SQL 见 `db/doll_schema.sql`。

## 5. 款式键对照表（AI 与管理台约束）

| 分类 code | 有效 style |
|---|---|
| hair | short, bob, long, twintails, bun, spiky |
| top | tee, hoodie, shirt, vest, sweater, jacket |
| bottom | shorts, pants, skirt, wide_leg |
| scarf | scarf, bandana |
| hat | beanie, cap, bucket, beret |
| shoes | sneakers, boots, loafers, sandals |
| accessory | glasses, necklace, backpack, earrings, flower, watch |
