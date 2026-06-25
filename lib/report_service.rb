require_relative 'data_store'
require_relative 'inventory_service'
require_relative 'order_service'
require 'date'

module ReportService
  def self.daily_report(store_id, date_str = nil)
    store = DataStore.find_store(store_id)
    return { error: '门店不存在', status: 400 } unless store

    if date_str.nil? || date_str.to_s.empty?
      target_date = Date.today.prev_day
    else
      begin
        target_date = Date.parse(date_str)
      rescue ArgumentError
        return { error: '日期格式无效，请使用 YYYY-MM-DD，如 2026-06-25', status: 400 }
      end
    end

    date_s = target_date.strftime('%Y-%m-%d')

    inv_summary = InventoryService.consumption_summary_by_date(store_id, date_s)
    ord_summary = OrderService.daily_summary(store_id, date_s)

    if inv_summary[:error]
      return inv_summary
    end
    if ord_summary[:error]
      return ord_summary
    end

    no_data = inv_summary[:no_data] && ord_summary[:no_data]
    data_hints = []
    data_hints << inv_summary[:note] if inv_summary[:no_data]
    data_hints << ord_summary[:note] if ord_summary[:no_data]

    {
      report_type: 'daily',
      generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      store_id: store_id,
      store_name: store['name'],
      date: date_s,
      weekday: %w[星期日 星期一 星期二 星期三 星期四 星期五 星期六][target_date.wday],
      no_data: no_data,
      friendly_hint: no_data ? "#{store['name']} #{date_s} 暂无经营数据，可能当天未营业或数据尚未录入" : nil,
      inventory: {
        total_consumed_kg: inv_summary[:total_consumed_kg],
        bean_breakdown: inv_summary[:bean_breakdown],
        no_data: inv_summary[:no_data],
        note: inv_summary[:no_data] ? inv_summary[:note] : nil
      },
      orders: {
        total_orders: ord_summary[:total_orders],
        total_cups: ord_summary[:total_cups],
        most_popular_bean: ord_summary[:most_popular_bean],
        bean_rank: ord_summary[:bean_rank],
        no_data: ord_summary[:no_data],
        note: ord_summary[:no_data] ? ord_summary[:note] : nil
      },
      insights: build_insights(inv_summary, ord_summary, store['name'], date_s)
    }
  end

  def self.build_insights(inv, ord, store_name, date_s)
    insights = []

    if inv[:no_data] && ord[:no_data]
      insights << "📌 #{store_name} 在 #{date_s} 没有记录到消耗或订单数据"
      return insights
    end

    unless inv[:no_data]
      insights << "☕ 当日共消耗豆子 #{inv[:total_consumed_kg]} 公斤，涉及 #{inv[:bean_breakdown].size} 个品种"
      top_bean = inv[:bean_breakdown].first
      if top_bean
        insights << "📊 消耗最多的是「#{top_bean[:bean_name]}」，用了 #{top_bean[:consumed_kg]} 公斤"
      end
    end

    unless ord[:no_data]
      insights << "🧾 当日共完成 #{ord[:total_orders]} 笔订单，合计 #{ord[:total_cups]} 杯"
      if ord[:most_popular_bean]
        mp = ord[:most_popular_bean]
        insights << "🏆 最受欢迎豆子是「#{mp[:bean_name]}」，售出 #{mp[:cups]} 杯，占比 #{mp[:share]}"
      end
    end

    if !inv[:no_data] && !ord[:no_data] && ord[:total_cups] > 0
      per_cup = (inv[:total_consumed_kg] * 1000 / ord[:total_cups]).round(1)
      insights << "📈 平均每杯用豆约 #{per_cup} 克（供参考）"
    end

    insights
  end
end
