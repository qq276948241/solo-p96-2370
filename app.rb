require 'sinatra'
require 'sinatra/json'

require_relative 'lib/data_store'
require_relative 'lib/inventory_service'
require_relative 'lib/order_service'
require_relative 'lib/report_service'

set :port, 3001
set :bind, '0.0.0.0'
set :environment, :development

before do
  content_type :json, charset: 'utf-8'
end

helpers do
  def parse_body
    return {} unless request.body.size > 0
    JSON.parse(request.body.read, symbolize_names: true)
  rescue JSON::ParserError
    halt 400, { error: 'JSON格式无效' }.to_json
  end

  def send_result(result)
    if result.key?(:error)
      code = result[:status] || 400
      body = { error: result[:error], **result.except(:error, :status) }.to_json
      halt code, body
    else
      status 200
      json result
    end
  end
end

get '/' do
  json(
    name: '社区咖啡店管理API',
    version: '1.1.0',
    port: settings.port,
    endpoints: {
      inventory: [
        'GET    /stores',
        'GET    /beans',
        'GET    /inventory/:store_id',
        'POST   /inventory/consume',
        'GET    /inventory/consumptions',
        'GET    /inventory/consumptions/:store_id',
        'GET    /inventory/alerts'
      ],
      orders: [
        'POST   /orders',
        'GET    /orders/:order_id',
        'GET    /orders',
        'PATCH  /orders/:order_id/cancel',
        'PATCH  /orders/:order_id/status'
      ],
      reports: [
        'GET    /reports/daily?store_id=xxx&date=YYYY-MM-DD'
      ]
    }
  )
end

# ============ 基础数据 ============

get '/stores' do
  json stores: DataStore.stores
end

get '/beans' do
  json beans: DataStore.beans
end

# ============ 豆子库存模块 ============

get '/inventory/alerts' do
  json InventoryService.replenish_alerts
end

get '/inventory/consumptions' do
  json InventoryService.consumption_history
end

get '/inventory/consumptions/:store_id' do
  json InventoryService.consumption_history(params[:store_id])
end

post '/inventory/consume' do
  body = parse_body
  required = %i[store_id bean_id amount_kg]
  missing = required.select { |k| body[k].nil? || body[k].to_s.empty? }
  unless missing.empty?
    halt 400, json(error: "缺少必填参数：#{missing.join('、')}")
  end
  result = InventoryService.record_consumption(
    body[:store_id],
    body[:bean_id],
    body[:amount_kg].to_f,
    body[:note]
  )
  send_result(result)
end

get '/inventory/:store_id' do
  result = InventoryService.list_by_store(params[:store_id])
  send_result(result)
end

# ============ 订单模块 ============

post '/orders' do
  body = parse_body
  required = %i[store_id pickup_time cup_size bean_id]
  missing = required.select { |k| body[k].nil? || body[k].to_s.empty? }
  unless missing.empty?
    halt 400, json(error: "缺少必填参数：#{missing.join('、')}")
  end
  result = OrderService.create_order(body)
  send_result(result)
end

get '/orders/:order_id' do
  result = OrderService.get_order(params[:order_id])
  send_result(result)
end

get '/orders' do
  result = OrderService.list_orders(
    store_id: params[:store_id],
    status: params[:status],
    customer_name: params[:customer_name]
  )
  json result
end

patch '/orders/:order_id/cancel' do
  body = parse_body
  result = OrderService.cancel_order(params[:order_id], body[:reason])
  send_result(result)
end

patch '/orders/:order_id/status' do
  body = parse_body
  unless body[:status] && !body[:status].empty?
    halt 400, json(error: '缺少必填参数：status')
  end
  result = OrderService.update_status(params[:order_id], body[:status])
  send_result(result)
end

# ============ 报表模块 ============

get '/reports/daily' do
  unless params[:store_id] && !params[:store_id].empty?
    halt 400, json(error: '缺少必填参数：store_id，例如 /reports/daily?store_id=store_1&date=2026-06-25')
  end
  result = ReportService.daily_report(params[:store_id], params[:date])
  send_result(result)
end

not_found do
  json error: '接口不存在', path: request.path_info
end

error 500 do
  json error: '服务器内部错误', message: env['sinatra.error']&.message
end
