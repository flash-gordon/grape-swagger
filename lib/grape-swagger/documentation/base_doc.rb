require 'set'

module GrapeSwagger
  class Documentation < Grape::API
    class BaseDoc
      PRIMITIVE_TYPES = %w(object integer long float double string byte boolean date dateTime).to_set

      attr_reader :documentation_class

      delegate :markdown, to: :documentation_class

      def initialize(documentation_class)
        @documentation_class = documentation_class
      end

      def as_markdown(description = nil)
        description && markdown ? markdown.as_markdown(strip_heredoc(description)) : description
      end

      def endpoint
        documentation_class.target_class
      end

      def type_to_ref(type)
        type = type.name.sub(/^[A-Z]/) { |f| f.downcase } if type.is_a?(Class)

        if PRIMITIVE_TYPES.include?(type)
          {'type' => type}
        else
          {'$ref' => type}
        end
      end

      def strip_heredoc(string)
        indent = string.scan(/^[ \t]*(?=\S)/).min.try(:size) || 0
        string.gsub(/^[ \t]{#{indent}}/, '')
      end

      def parse_entity_name(entity)
        if entity.respond_to?(:entity_name)
          entity.entity_name
        else
          stripped_model_name(entity)
        end
      end

      def stripped_model_name(entity)
        entity.to_s.gsub(/Entit(?:y|ies)/, '').gsub('::::', '::').gsub(/^::/, '')
      end
    end
  end
end