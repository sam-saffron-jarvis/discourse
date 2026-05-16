# frozen_string_literal: true

module DiscourseWorkflows
  module Item
    PAIRED_ITEM_KEY = "pairedItem"

    def self.wrap(data = nil, paired_item: nil, **keyword_data)
      data = keyword_data if data.nil? && keyword_data.present?

      case data
      when Array
        data.map { |d| wrap(d) }
      when Hash
        item = { "json" => data.deep_stringify_keys.freeze }
        item[PAIRED_ITEM_KEY] = normalize_paired_item(paired_item) if paired_item.present?
        item
      else
        raise ArgumentError, "Item.wrap expects Hash or Array<Hash>, got #{data.class}"
      end
    end

    def self.paired_item(item)
      item[PAIRED_ITEM_KEY]
    end

    def self.with_paired_item(item, paired_item)
      item.except(PAIRED_ITEM_KEY).merge(PAIRED_ITEM_KEY => normalize_paired_item(paired_item))
    end

    def self.normalize_paired_item(paired_item)
      case paired_item
      when Array
        paired_item.map { |entry| normalize_paired_item_entry(entry) }
      when Hash
        normalize_paired_item_entry(paired_item)
      when Integer
        { "item" => paired_item }
      else
        paired_item
      end
    end

    def self.normalize_paired_item_entry(entry)
      entry.deep_stringify_keys.compact
    end
  end
end
