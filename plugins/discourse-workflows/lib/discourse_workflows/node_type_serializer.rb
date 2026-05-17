# frozen_string_literal: true

module DiscourseWorkflows
  class NodeTypeSerializer
    def initialize(identifier:, available_versions:)
      @identifier = identifier
      @available_versions = available_versions
      @latest_version = available_versions.last
    end

    def to_h
      versions = version_descriptions
      latest = versions.fetch(@latest_version)
      schema_versions = versions.transform_values { |v| v[:property_schema] } if versions.size > 1

      latest.merge(
        property_versions: schema_versions,
        property_schema_versions: schema_versions,
        latest_version: @latest_version,
        available_versions: @available_versions,
        latest: latest,
        versions: versions,
        icon: latest.dig(:ui, :icon),
        color: latest.dig(:ui, :color),
        branching: latest.dig(:capabilities, :branching),
        manually_triggerable: latest.dig(:capabilities, :manually_triggerable),
      ).compact
    end

    private

    def version_descriptions
      @available_versions.index_with do |version|
        serializable_version(Registry.find_node_type(@identifier, version: version), version)
      end
    end

    def serializable_version(klass, version)
      output_schema = klass.output_schema
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
