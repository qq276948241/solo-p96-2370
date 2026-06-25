require_relative 'data_store'

module InventoryService
  include DataStore

  def self.list_by_store(store_id)
    store = DataStore.find_store(store_id)
    return { error: '门店不存在', status: 404 } unless store

    items = DataStore.inventory.select { |i| i['store_id'] == store_id }
    items_with_warning = items.map do |item|
      bean = DataStore.find_bean(item['bean_id'])
      low_stock = item['stock_kg'] < DataStore::REPLENISH_THRESHOLD_KG
      {
        bean_id: item['bean_id'],
        bean_name: bean ? bean['name'] : '未知豆子',
        origin: bean ? bean['origin'] : nil,
        flavor: bean ? bean['flavor'] : nil,
        stock_kg: item['stock_kg'],
        updated_at: item['updated_at'],
        low_stock_warning: low_stock,
        warning_message: low_stock ? "库存低于#{DataStore::REPLENISH_THRESHOLD_KG}公斤，请尽快补货" : nil
      }
    end
    {
      store_id: store_id,
      store_name: store['name'],
      inventory: items_with_warning,
      needs_replenishment: items_with_warning.any? { |i| i[:low_stock_warning] }
    }
  end

  def self.record_consumption(store_id, bean_id, amount_kg, note = nil)
    store = DataStore.find_store(store_id)
    return { error: '门店不存在', status: 404 } unless store

    bean = DataStore.find_bean(bean_id)
    return { error: '豆子品种不存在', status: 404 } unless bean

    inv = DataStore.find_inventory(store_id, bean_id)
    return { error: '该门店无此豆子库存记录', status: 404 } unless inv

    if amount_kg <= 0
      return { error: '消耗量必须大于0', status: 400 }
    end

    if inv['stock_kg'] < amount_kg
      return { error: "库存不足，当前余量#{inv['stock_kg']}公斤，无法消耗#{amount_kg}公斤", status: 400 }
    end

    inv['stock_kg'] = (inv['stock_kg'] - amount_kg).round(3)
    inv['updated_at'] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

    inventory_data = DataStore.inventory
    idx = inventory_data.index { |i| i['store_id'] == store_id && i['bean_id'] == bean_id }
    inventory_data[idx] = inv
    DataStore.save_inventory(inventory_data)

    consumption_record = {
      id: DataStore.generate_id('cons'),
      store_id: store_id,
      store_name: store['name'],
      bean_id: bean_id,
      bean_name: bean['name'],
      amount_kg: amount_kg,
      remaining_kg: inv['stock_kg'],
      note: note,
      created_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    }

    consumptions = DataStore.consumptions
    consumptions << consumption_record
    DataStore.save_consumptions(consumptions)

    low_stock = inv['stock_kg'] < DataStore::REPLENISH_THRESHOLD_KG
    {
      success: true,
      consumption: consumption_record,
      low_stock_warning: low_stock,
      warning_message: low_stock ? "#{bean['name']}库存已降至#{inv['stock_kg']}公斤，请尽快补货" : nil
    }
  end

  def self.consumption_history(store_id = nil)
    records = DataStore.consumptions
    records = records.select { |r| r['store_id'] == store_id } if store_id
    { total: records.size, records: records.sort_by { |r| r['created_at'] }.reverse }
  end

  def self.replenish_alerts
    low_items = []
    DataStore.inventory.each do |item|
      next unless item['stock_kg'] < DataStore::REPLENISH_THRESHOLD_KG
      store = DataStore.find_store(item['store_id'])
      bean = DataStore.find_bean(item['bean_id'])
      low_items << {
        store_id: item['store_id'],
        store_name: store ? store['name'] : '未知门店',
        bean_id: item['bean_id'],
        bean_name: bean ? bean['name'] : '未知豆子',
        current_stock_kg: item['stock_kg'],
        threshold_kg: DataStore::REPLENISH_THRESHOLD_KG,
        shortage_kg: (DataStore::REPLENISH_THRESHOLD_KG - item['stock_kg']).round(3),
        suggestion: "建议补货至少#{(DataStore::REPLENISH_THRESHOLD_KG * 2 - item['stock_kg']).round(1)}公斤"
      }
    end
    {
      total_alerts: low_items.size,
      threshold_kg: DataStore::REPLENISH_THRESHOLD_KG,
      alerts: low_items.sort_by { |a| a[:current_stock_kg] }
    }
  end
end
