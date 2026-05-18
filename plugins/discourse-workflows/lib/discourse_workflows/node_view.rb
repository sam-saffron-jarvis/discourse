# frozen_string_literal: true

module DiscourseWorkflows
  class NodeView
    attr_reader :id, :name, :type, :type_version, :position, :disabled, :webhook_id

    def self.from_snapshot_node(
      node,
      include_node_parameters: false,
      include_credentials: false,
      include_webhook_id: false
    )
      return if node.blank?

      new(
        id: node.id,
        name: node.name,
        type: node.type,
        type_version: node.type_version,
        position: node.position,
        disabled: node.respond_to?(:disabled) ? node.disabled : false,
        webhook_id: include_webhook_id ? node.webhook_id : nil,
        parameters: include_node_parameters ? node.parameters : nil,
        credentials: include_credentials ? node.credentials : nil,
      )
    end

    def initialize(
      id:,
      name:,
      type:,
      type_version:,
      position: nil,
      disabled: false,
      webhook_id: nil,
      parameters: nil,
      credentials: nil
    )
      @id = id.to_s
      @name = name.to_s
      @type = type.to_s
      @type_version = numeric_version(type_version)
      @position = position || [0, 0]
      @disabled = !!disabled
      @webhook_id = webhook_id
      @parameters = parameters&.deep_dup
      @credentials = credentials&.deep_dup
      freeze
    end

    def parameters
      @parameters&.deep_dup
    end

    def credentials
      @credentials&.deep_dup
    end

    def to_h
      {
        "id" => id,
        "name" => name,
        "type" => type,
        "typeVersion" => type_version,
        "position" => position,
        "disabled" => disabled,
        "webhookId" => webhook_id,
        "parameters" => parameters,
        "credentials" => credentials,
      }.compact
    end

    private

    def numeric_version(version)
      Float(version)
    rescue ArgumentError, TypeError
      version
    end
  end
end
