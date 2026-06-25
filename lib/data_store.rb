require 'json'
require 'fileutils'

module DataStore
  DATA_DIR = File.join(__dir__, '..', 'data')
  REPLENISH_THRESHOLD_KG = 2.0

  def self.data_path(filename)
    File.join(DATA_DIR, filename)
  end

  def self.read_json(filename)
    path = data_path(filename)
    return [] unless File.exist?(path)
    content = File.read(path, encoding: 'UTF-8')
    JSON.parse(content)
  rescue JSON::ParserError
    []
  end

  def self.write_json(filename, data)
    path = data_path(filename)
    File.write(path, JSON.pretty_generate(data), encoding: 'UTF-8')
  end

  def self.stores
    read_json('stores.json')
  end

  def self.beans
    read_json('beans.json')
  end

  def self.inventory
    read_json('inventory.json')
  end

  def self.save_inventory(data)
    write_json('inventory.json', data)
  end

  def self.consumptions
    read_json('consumptions.json')
  end

  def self.save_consumptions(data)
    write_json('consumptions.json', data)
  end

  def self.orders
    read_json('orders.json')
  end

  def self.save_orders(data)
    write_json('orders.json', data)
  end

  def self.find_store(store_id)
    stores.find { |s| s['id'] == store_id }
  end

  def self.find_bean(bean_id)
    beans.find { |b| b['id'] == bean_id }
  end

  def self.find_inventory(store_id, bean_id)
    inventory.find { |i| i['store_id'] == store_id && i['bean_id'] == bean_id }
  end

  def self.find_order(order_id)
    orders.find { |o| o['id'] == order_id }
  end

  def self.generate_id(prefix)
    "#{prefix}_#{Time.now.to_i}_#{rand(1000..9999)}"
  end
end
