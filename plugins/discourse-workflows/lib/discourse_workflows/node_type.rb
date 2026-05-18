# frozen_string_literal: true

module DiscourseWorkflows
  class NodeType
    include NodeErrorHandling
    extend NodeTypeDescriptor

    DESCRIPTION_DEFAULTS = {
      version: "1.0",
      defaults: {
      },
      inputs: [:main],
      required_inputs: nil,
      outputs: [:main],
      properties: {
      },
      output_schema: {
      },
      credentials: [],
      webhooks: [],
      events: [],
      max_nodes: nil,
      capabilities: {
      },
      palette_visible: true,
      available: true,
    }.freeze

    TYPE_EXEMPLARS = {
      string: "",
      integer: 0,
      number: 0,
      boolean: false,
      array: [],
      object: {
      },
    }.freeze

    def self.inherited(subclass)
      super
      DiscourseWorkflows::NodeType.registered_nodes << subclass
    end

    def self.registered_nodes
      @registered_nodes ||= []
    end

    def self.waiting_identifiers
      registered_nodes.select(&:waits_for_resume?).map(&:identifier)
    end

    def self.description(value = nil)
      if value
        @description = DESCRIPTION_DEFAULTS.deep_merge(value.deep_symbolize_keys).freeze
      else
        @description || DESCRIPTION_DEFAULTS
      end
    end

    def self.identifier
      description.fetch(:name) { raise NotImplementedError }
    end

    def self.version
      description.fetch(:version)
    end

    def self.icon
      description.dig(:defaults, :icon)
    end

    def self.color
      description.dig(:defaults, :color)
    end

    def self.palette_visible?
      description_value(:palette_visible)
    end

    def self.available?
      description_value(:available)
    end

    def self.unavailable_reason_key
      description[:unavailable_reason_key]
    end

    def self.inputs(configuration = {})
      description_value(:inputs, configuration: configuration)
    end

    def self.outputs(configuration = {})
      description_value(:outputs, configuration: configuration)
    end

    def self.properties
      description_value(:properties)
    end

    def self.credentials
      description_value(:credentials)
    end

    def self.webhooks(configuration = {})
      Array(description_value(:webhooks, configuration: configuration)).map do |webhook|
        webhook.deep_symbolize_keys
      end
    end

    def self.waiting_webhook_for(http_method:, path:, node_type:)
      webhooks.find do |webhook|
        webhook[:restart_webhook] == true && webhook[:node_type].to_s == node_type.to_s &&
          webhook[:http_method].to_s.casecmp?(http_method.to_s) &&
          webhook.fetch(:path) { "" }.to_s == path.to_s
      end
    end

    def self.property_schema
      properties
    end

    def self.event_name
      Array(description[:events]).first
    end

    def self.manually_triggerable?
      capability_enabled?(:manually_triggerable)
    end

    def self.provides_current_user?
      capability_enabled?(:provides_current_user)
    end

    def self.waits_for_resume?
      capability_enabled?(:waits_for_resume)
    end

    def self.output_schema
      description_value(:output_schema)
    end

    def self.max_nodes
      description_value(:max_nodes)
    end

    def self.output_exemplar
      exemplar_from_schema(output_schema)
    end

    def self.exemplar_from_schema(schema)
      schema.each_with_object({}) { |(key, value), hash| hash[key.to_s] = exemplar_value(value) }
    end

    def self.exemplar_value(value)
      return TYPE_EXEMPLARS.fetch(value, "") unless value.is_a?(Hash)
      return exemplar_from_schema(value) unless value.key?(:type)
      if value[:type] == :object && value[:fields].is_a?(Hash)
        return exemplar_from_schema(value[:fields])
      end

      TYPE_EXEMPLARS.fetch(value[:type], "")
    end

    def self.schema_extensions
      @schema_extensions || []
    end

    def self.extend_schema(name, fields:, serializer:)
      @schema_extensions ||= []
      @schema_extensions << { name: name, fields: fields, serializer: serializer }
    end

    def self.description_value(key, configuration: nil)
      value = description.fetch(key)
      return value unless value.respond_to?(:call)

      configuration.nil? ? value.call : value.call(configuration)
    end

    def self.capability_enabled?(key)
      description.dig(:capabilities, key) == true
    end

    def initialize(**)
    end

    def execute(exec_ctx)
      raise NotImplementedError
    end

    def trigger(trigger_ctx)
      raise NotImplementedError
    end

    def webhook(webhook_ctx)
      raise NotImplementedError
    end

    def valid?
      true
    end

    def output
      raise NotImplementedError
    end

    private

    def map_input_items(exec_ctx)
      [
        exec_ctx.input_items.map.with_index do |item, item_index|
          wrap(yield(exec_ctx.get_node_parameters(item_index), item, item_index))
        end,
      ]
    end

    def wrap(data, paired_item: nil)
      Item.wrap(data, paired_item:)
    end

    def with_paired_item(item, paired_item)
      Item.with_paired_item(item, paired_item)
    end

    def skip_workflows?(opts)
      opts.is_a?(Hash) && opts.with_indifferent_access[:skip_workflows]
    end
  end
end
