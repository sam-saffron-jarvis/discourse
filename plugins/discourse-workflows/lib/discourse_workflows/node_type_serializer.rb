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

      latest.merge(
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
      properties = klass.property_schema
      description =
        klass
          .description
          .except(:output_schema)
          .merge(
            displayName: klass.label_key,
            descriptionKey: klass.description_key,
            name: @identifier,
            version: version,
            inputs: klass.input_ports,
            outputs: klass.ports,
            properties: properties,
            outputSchema: output_schema,
          )

      {
        displayName: description[:displayName],
        name: @identifier,
        version: version,
        defaults: description[:defaults],
        inputs: description[:inputs],
        outputs: description[:outputs],
        properties: properties,
        outputSchema: output_schema,
        credentials: description[:credentials],
        webhooks: description[:webhooks],
        description: description,
        identifier: @identifier,
        kind: klass.kind,
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
