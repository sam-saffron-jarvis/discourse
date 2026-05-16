# frozen_string_literal: true

module DiscourseWorkflows
  class NodeTypeSerializer
    def initialize(identifier:, latest_class:, latest_version:, available_versions:)
      @identifier = identifier
      @latest_class = latest_class
      @latest_version = latest_version
      @available_versions = available_versions
    end

    def to_h
      latest = serializable_version(@latest_class, @latest_version)
      description = latest[:description]
      ui = latest[:ui]
      capabilities = latest[:capabilities]

      {
        displayName: description[:displayName],
        name: @identifier,
        version: @latest_version,
        defaults: description[:defaults],
        inputs: description[:inputs],
        outputs: description[:outputs],
        properties: description[:properties],
        property_versions: property_schema_versions,
        outputSchema: latest[:output_schema],
        credentials: description[:credentials],
        webhooks: description[:webhooks],
        description: description,
        identifier: @identifier,
        kind: @latest_class.kind,
        latest_version: @latest_version,
        available_versions: @available_versions,
        latest: latest,
        versions: version_descriptions,
        property_schema: @latest_class.property_schema,
        property_schema_versions: property_schema_versions,
        output_schema: latest[:output_schema],
        ui: ui,
        capabilities: capabilities,
        ports: latest[:outputs],
        operations: latest[:operations],
        icon: ui[:icon],
        color: ui[:color],
        branching: capabilities[:branching],
        manually_triggerable: capabilities[:manually_triggerable],
        available: @latest_class.available?,
        unavailable_reason_key:
          (@latest_class.unavailable_reason_key unless @latest_class.available?),
      }.compact
    end

    private

    def version_descriptions
      @available_versions.to_h do |version|
        klass = Registry.find_node_type(@identifier, version: version)
        [version, serializable_version(klass, version)]
      end
    end

    def property_schema_versions
      return if @available_versions.size <= 1

      @available_versions.to_h do |version|
        [version, Registry.find_node_type(@identifier, version: version).property_schema]
      end
    end

    def serializable_version(klass, version)
      output_schema = klass.respond_to?(:output_schema) ? klass.output_schema : {}
      description =
        klass.description.merge(
          displayName: klass.label_key,
          descriptionKey: klass.description_key,
          name: @identifier,
          version: version,
          inputs: klass.input_ports,
          outputs: klass.ports,
          properties: klass.properties,
          output_schema: output_schema,
        )

      {
        displayName: description[:displayName],
        name: @identifier,
        version: version,
        defaults: description[:defaults],
        inputs: description[:inputs],
        outputs: description[:outputs],
        properties: description[:properties],
        outputSchema: output_schema,
        credentials: description[:credentials],
        webhooks: description[:webhooks],
        description: description,
        identifier: @identifier,
        kind: klass.kind,
        property_schema: klass.property_schema,
        output_schema: output_schema,
        ui: klass.ui_metadata,
        capabilities: klass.capabilities,
        ports: klass.ports,
        operations: klass.operations,
        available: klass.available?,
        unavailable_reason_key: (klass.unavailable_reason_key unless klass.available?),
      }.compact
    end
  end
end
