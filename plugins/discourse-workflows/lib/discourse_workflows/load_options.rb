# frozen_string_literal: true

module DiscourseWorkflows
  module LoadOptions
    CONTEXT_PARAMETER_NAMES = %i[context load_options_context].freeze

    module_function

    def call(node_class, context)
      if node_class.respond_to?(:load_options_context)
        return node_class.load_options_context(context)
      end
      return unless node_class.respond_to?(:load_options)

      node_class.load_options(
        context_aware_load_options?(node_class) ? context : context.source_key,
      )
    end

    def context_aware_load_options?(node_class)
      node_class
        .method(:load_options)
        .parameters
        .any? { |_, name| CONTEXT_PARAMETER_NAMES.include?(name) }
    end
  end
end
