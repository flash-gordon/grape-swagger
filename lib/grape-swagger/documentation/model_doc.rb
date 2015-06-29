module GrapeSwagger
  module Documentation
    class ModelDoc < BaseDoc
      # TODO: Add caching
      def self.fetch(model, documentation_class)
        new(model, documentation_class)
      end

      attr_reader :model

      def initialize(model, documentation_class)
        super(documentation_class)
        @model = model
      end

      def properties
        model.documentation.reduce({}) do |props, (property_name, property_info)|
          props[property_name] = transform_property(property_info, property_name)
          props
        end
      end

      def transform_property(property, name)
        p = property.except(:required)

        type = p.delete(:type) do
          if (entity = model.exposures[name][:using])
            parse_entity_name(entity)
          end
        end

        if p.delete(:is_array)
          p[:items] = type_to_ref(type)
          p[:type] = 'array'
        else
          p.merge! type_to_ref(type)
        end

        property_description = p.delete(:desc) { translate(name) }
        p[:description] = property_description if property_description

        # rename Grape's 'values' to 'enum'
        select_values = p.delete(:values)
        if select_values
          select_values = select_values.call if select_values.is_a?(Proc)
          p[:enum] = select_values
        end

        p
      end

      def required_properties
        model.documentation.map do |(property_name, property_info)|
          property_name.to_s if property_info[:required]
        end.compact
      end

      def id
        model.instance_variable_get(:@root) || name
      end

      def name
        parse_entity_name(model)
      end

      def translate(key)
        I18n.t([model.to_s.underscore.gsub('/', '.'), key].join('.'), default: '').presence
      end
    end
  end
end
