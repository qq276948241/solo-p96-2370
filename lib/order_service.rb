require_relative 'data_store'
require 'time'

module OrderService
  include DataStore

  VALID_CUP_SIZES = %w[小杯 中杯 大杯 超大杯]
  STATUS_PENDING = 'pending'
  STATUS_MAKING = 'making'
  STATUS_READY = 'ready'
  STATUS_COMPLETED = 'completed'
  STATUS_CANCELLED = 'cancelled'

  CANCELLABLE_STATUSES = [STATUS_PENDING].freeze

  def self.create_order(params)
    store_id = params[:store_id]
    pickup_time = params[:pickup_time]
    cup_size = params[:cup_size]
    bean_id = params[:bean_id]
    customer_name = params[:customer_name] || '匿名顾客'
    quantity = params[:quantity] || 1
    note = params[:note]

    store = DataStore.find_store(store_id)
    return { error: '门店不存在', status: 404 } unless store

    bean = DataStore.find_bean(bean_id)
    return { error: '豆子品种不存在', status: 404 } unless bean

    unless VALID_CUP_SIZES.include?(cup_size)
      return { error: "杯型无效，可选值：#{VALID_CUP_SIZES.join('、')}", status: 400 }
    end

    begin
      parsed_pickup = Time.parse(pickup_time)
    rescue ArgumentError, TypeError
      return { error: '取单时间格式无效，请使用ISO 8601格式如2026-06-26T10:30:00+08:00', status: 400 }
    end

    inv = DataStore.find_inventory(store_id, bean_id)
    unless inv && inv['stock_kg'] > 0
      return { error: '该门店当前无此豆子可用库存', status: 400 }
    end

    order = {
      id: DataStore.generate_id('order'),
      store_id: store_id,
      store_name: store['name'],
      pickup_time: parsed_pickup.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
      pickup_time_local: parsed_pickup.strftime('%Y-%m-%d %H:%M:%S'),
      cup_size: cup_size,
      bean_id: bean_id,
      bean_name: bean['name'],
      customer_name: customer_name,
      quantity: quantity.to_i,
      note: note,
      status: STATUS_PENDING,
      status_text: '待制作',
      created_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    }

    orders = DataStore.orders
    orders << order
    DataStore.save_orders(orders)

    { success: true, order: order }
  end

  def self.get_order(order_id)
    order = DataStore.find_order(order_id)
    return { error: '订单不存在', status: 404 } unless order
    { order: decorate_order(order) }
  end

  def self.list_orders(store_id: nil, status: nil, customer_name: nil)
    orders = DataStore.orders
    orders = orders.select { |o| o['store_id'] == store_id } if store_id
    orders = orders.select { |o| o['status'] == status } if status
    if customer_name && !customer_name.empty?
      orders = orders.select { |o| o['customer_name'].include?(customer_name) }
    end
    decorated = orders.map { |o| decorate_order(o) }
                      .sort_by { |o| o[:created_at] }
                      .reverse
    { total: decorated.size, orders: decorated }
  end

  def self.cancel_order(order_id, reason = nil)
    orders = DataStore.orders
    idx = orders.index { |o| o['id'] == order_id }
    return { error: '订单不存在', status: 404 } unless idx

    order = orders[idx]
    unless CANCELLABLE_STATUSES.include?(order['status'])
      return {
        error: "订单当前状态为「#{order['status_text']}」，仅待制作状态的订单可取消",
        current_status: order['status'],
        status: 400
      }
    end

    order['status'] = STATUS_CANCELLED
    order['status_text'] = '已取消'
    order['cancelled_at'] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    order['cancel_reason'] = reason if reason

    orders[idx] = order
    DataStore.save_orders(orders)

    { success: true, message: '订单已成功取消', order: decorate_order(order) }
  end

  def self.update_status(order_id, new_status)
    valid_transitions = {
      STATUS_PENDING => [STATUS_MAKING, STATUS_CANCELLED],
      STATUS_MAKING => [STATUS_READY, STATUS_CANCELLED],
      STATUS_READY => [STATUS_COMPLETED],
      STATUS_COMPLETED => [],
      STATUS_CANCELLED => []
    }

    orders = DataStore.orders
    idx = orders.index { |o| o['id'] == order_id }
    return { error: '订单不存在', status: 404 } unless idx

    order = orders[idx]
    allowed = valid_transitions[order['status']] || []
    unless allowed.include?(new_status)
      return {
        error: "状态流转不合法：#{order['status_text']} 不能转为 #{status_text(new_status)}",
        current_status: order['status'],
        status: 400
      }
    end

    order['status'] = new_status
    order['status_text'] = status_text(new_status)
    order["#{new_status}_at"] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

    orders[idx] = order
    DataStore.save_orders(orders)

    { success: true, order: decorate_order(order) }
  end

  def self.status_text(status)
    case status
    when STATUS_PENDING then '待制作'
    when STATUS_MAKING then '制作中'
    when STATUS_READY then '待取餐'
    when STATUS_COMPLETED then '已完成'
    when STATUS_CANCELLED then '已取消'
    else '未知'
    end
  end

  def self.decorate_order(order)
    {
      id: order['id'],
      store_id: order['store_id'],
      store_name: order['store_name'],
      pickup_time: order['pickup_time'],
      pickup_time_local: order['pickup_time_local'],
      cup_size: order['cup_size'],
      bean_id: order['bean_id'],
      bean_name: order['bean_name'],
      customer_name: order['customer_name'],
      quantity: order['quantity'],
      note: order['note'],
      status: order['status'],
      status_text: order['status_text'],
      cancellable: CANCELLABLE_STATUSES.include?(order['status']),
      created_at: order['created_at'],
      cancelled_at: order['cancelled_at'],
      cancel_reason: order['cancel_reason']
    }
  end
end
