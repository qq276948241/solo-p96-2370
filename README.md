# 社区咖啡店管理系统 API

基于 Ruby + Sinatra 的轻量级后端，管理三家社区咖啡店的豆子库存和顾客预约取单。

## 环境要求

- Ruby >= 3.0

## 安装依赖

```bash
bundle install
```

## 启动服务

```bash
ruby app.rb
# 或
bundle exec rackup -p 3001
```

服务启动后监听 3001 端口：`http://localhost:3001`

## 数据存储

所有数据使用 JSON 文件存储在 `data/` 目录下：

- `stores.json` - 门店信息（3 家门店）
- `beans.json` - 豆子品种信息
- `inventory.json` - 各门店豆子库存
- `consumptions.json` - 消耗记录
- `orders.json` - 订单记录

## 接口清单

### 基础数据

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/` | API 信息总览 |
| GET | `/stores` | 查询所有门店 |
| GET | `/beans` | 查询所有豆子品种 |

### 豆子库存模块

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/inventory/:store_id` | 按门店查当前余量（低于2kg自动附警告） |
| POST | `/inventory/consume` | 记录每日消耗 |
| GET | `/inventory/consumptions` | 查全部消耗记录 |
| GET | `/inventory/consumptions/:store_id` | 查某门店消耗记录 |
| GET | `/inventory/alerts` | 查所有门店补货警告清单 |

### 订单模块

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/orders` | 顾客下单 |
| GET | `/orders/:order_id` | 查单个订单状态 |
| GET | `/orders` | 查订单列表（支持按门店/状态/顾客名筛选） |
| PATCH | `/orders/:order_id/cancel` | 取消还没开始做的订单 |
| PATCH | `/orders/:order_id/status` | 更新订单状态（待制作→制作中→待取餐→已完成） |

## 接口示例

### 查某门店库存余量

```bash
curl http://localhost:3001/inventory/store_1
```

响应中低于 2kg 的豆子会自动带 `low_stock_warning: true`。

### 记录消耗

```bash
curl -X POST http://localhost:3001/inventory/consume \
  -H "Content-Type: application/json" \
  -d '{"store_id":"store_1","bean_id":"bean_2","amount_kg":0.5,"note":"早高峰消耗"}'
```

### 顾客下单

```bash
curl -X POST http://localhost:3001/orders \
  -H "Content-Type: application/json" \
  -d '{
    "store_id":"store_2",
    "pickup_time":"2026-06-26T10:30:00+08:00",
    "cup_size":"中杯",
    "bean_id":"bean_1",
    "customer_name":"张三",
    "quantity":2,
    "note":"少冰"
  }'
```

### 取消订单（仅待制作可取消）

```bash
curl -X PATCH http://localhost:3001/orders/xxx/cancel \
  -H "Content-Type: application/json" \
  -d '{"reason":"临时有事"}'
```

### 查看所有补货警告

```bash
curl http://localhost:3001/inventory/alerts
```

## 订单状态流转

```
pending（待制作）→ making（制作中）→ ready（待取餐）→ completed（已完成）
         ↓                 ↓
    cancelled（已取消）  cancelled（已取消）
```
