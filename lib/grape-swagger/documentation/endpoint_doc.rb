module GrapeSwagger
  class Documentation < Grape::API
    class RouteDoc < BaseDoc
      attr_reader :endpoint, :route, :route_options

      PARAM_DEFAULTS = {
          description: nil,
          required: false,
          default: nil,
          is_array: false,
          values: nil,
          type: 'string'
      }

      def initialize(documentation_class, endpoint, route)
        super(documentation_class)

        @endpoint = endpoint
        @route_options = route.instance_variable_get(:@options)
      end

      def parameters
        header_params + parse_params
      end

      def method
        route_options[:method]
      end

      def path
        route_options[:path]
      end

      def params
        route_options[:params] || []
      end

      def header_params
        (route_options[:headers]|| []).map do |param, value|
          if value.is_a?(Hash)
            value_hash = value
          else
            value_hash = {
                description: nil,
                required: false,
                default: nil
            }
          end

          parsed_params = {
              paramType: 'header',
              name: param,
              description: get_description(value_hash, param),
              type: translate_data_type('string'),
              required: !!value_hash[:required]
          }

          parsed_params[:defaultValue] = value_hash[:default] if value_hash[:default]

          parsed_params
        end
      end

      def select_data_type(raw_data_type)
        case raw_data_type
          when 'Hash'
            'object'
          when 'Rack::Multipart::UploadedFile'
            'File'
          when 'Virtus::Attribute::Boolean'
            'boolean'
          when 'Boolean', 'Date', 'Integer', 'String', 'Float'
            raw_data_type.downcase
          when 'BigDecimal'
            'long'
          when 'DateTime'
            'dateTime'
          when 'Numeric', 'Float'
            'double'
          when 'Symbol'
            'string'
          else
            parse_entity_name(raw_data_type)
        end
      end

      def select_param_type(data_type, param)
        case
          when path.include?(":#{param}")
            'path'
          when %w(POST PUT PATCH).include?(method)
            if PRIMITIVE_TYPES.include?(data_type)
              'form'
            else
              'body'
            end
          else
            'query'
        end
      end

      def get_param_values(raw_values)
        case raw_values
          when Range then raw_values.to_a
          when Proc  then raw_values.call
          else            raw_values
        end
      end

      def get_description(values, name)
        s = values[:desc] || values[:description] || translate(values.fetch(:documentation, {}).fetch(:i18n_key, name))

        as_markdown(s.is_a?(Proc) ? s.call : s)
      end

      def parse_params
        non_nested_params.map do |param, value|
          if value.is_a?(Hash)
            values_hash = value
          else
            values_hash = PARAM_DEFAULTS
          end

          description = get_description(values_hash, param)
          is_array = !!values_hash[:is_array]

          enum_values = get_param_values(values_hash[:values])

          data_type = select_data_type(values_hash[:type] || 'string')

          parsed_params = {
              paramType:     values_hash.fetch(:param_type) { select_param_type(data_type, param) },
              name:          values_hash[:full_name] || param,
              description:   description,
              type:          is_array ? 'array' : translate_data_type(data_type),
              required:      !!values_hash[:required],
              allowMultiple: is_array
          }
          parsed_params[:format] = 'int32' if data_type == 'integer'
          parsed_params[:format] = 'int64' if data_type == 'long'
          parsed_params[:items] = {'$ref' => translate_data_type(data_type)} if is_array
          parsed_params[:defaultValue] = values_hash[:default] if values_hash[:default]
          parsed_params[:enum] = enum_values if enum_values
          parsed_params
        end
      end

      def parse_array_params
        modified_params = {}
        array_param = nil
        params.each_key do |k|
          if params[k].is_a?(Hash) && params[k][:type] == 'Array'
            array_param = k
          else
            new_key = k
            unless array_param.nil?
              if k.to_s.start_with?(array_param.to_s + '[')
                new_key = array_param.to_s + '[]' + k.to_s.split(array_param)[1]
              end
            end
            modified_params[new_key] = params[k]
          end
        end
        modified_params
      end

      def non_nested_params(params = parse_array_params)
        # Duplicate the params as we are going to modify them
        dup_params = params.each_with_object(Hash.new) do |(param, value), dparams|
          dparams[param] = value.dup
        end

        dup_params.reject do |param, value|
          is_nested_param = /^#{ Regexp.quote param }\[.+\]$/
          0 < dup_params.count do |p, _|
            match = p.match(is_nested_param)
            dup_params[p][:required] = false if match && !value[:required]
            match
          end
        end
      end

      def app
        endpoint.options[:app]
      end

      def translate(key)
        I18n.t([app.name.underscore.gsub('/', '.'), key].join('.'), default: '').presence if app
      end

      def translated_description
        case route_options[:description]
          when Proc   then route_options[:description].call
          when String then route_options[:description]
          else translate('routes.' + description_nickname_key) || description_nickname_key
        end
      end

      def nickname
        route_options[:nickname] || method + path.gsub(/[\/:\(\)\.]/, '-')
      end

      def description_nickname_key
        nickname.gsub(/\s+/, '-').gsub('--version', '').gsub(/format-$/, '').gsub(/-+/, '-').chomp('-').downcase
      end
    end

    class EndpointDoc < BaseDoc
      attr_reader :routes_name

      delegate :api_version, :root_base_path, :authorizations, :base_path, to: :documentation_class
      
      def initialize(documentation_class, routes_name)
        super(documentation_class)
        @routes_name = routes_name
      end

      def routes
        endpoint.combined_namespace_routes[routes_name] || []
      end

      def visible_operations
        routes.reject do |(route, _)|
          route.route_hidden.respond_to?(:call) ? route.route_hidden.call : route.route_hidden
        end
      end

      def grouped_operations
        visible_operations.group_by do |(route, _)|
          parse_path(route.route_path, api_version)
        end
      end

      def resource_path
        path = if endpoint.combined_namespace_identifiers.key?(routes_name)
          endpoint.combined_namespace_identifiers[routes_name]
        else
          routes_name
        end

        '/%s' % path
      end

      def content_types
        content_types = (endpoint.content_types || {}).values

        if content_types.empty?
          formats       = [endpoint.format, endpoint.default_format].compact.uniq
          formats       = Grape::Formatter::Base.formatters({}).keys if formats.empty?
          content_types = Grape::ContentTypes::CONTENT_TYPES.select { |content_type, _mime_type| formats.include? content_type }.values
        end

        content_types.uniq
      end

      def description(request)
        models = Set.new(documentation_class.models)

        apis = grouped_operations.map do |(path, op_routes)|
          operations = op_routes.map do |(route, endpoint)|
            notes = as_markdown(route.route_notes)

            http_codes, extra_models = parse_http_codes(route.route_http_codes)

            models |= extra_models | Array(route.route_entity || [])

            route_doc = RouteDoc.new(documentation_class, endpoint, route)

            operation = {
                notes: notes.to_s,
                summary: route_doc.translated_description || '',
                nickname: route_doc.nickname,
                method: route_doc.method,
                parameters: route_doc.parameters,
                type: 'void'
            }
            operation[:authorizations] = route.route_authorizations unless route.route_authorizations.nil? || route.route_authorizations.empty?
            if operation[:parameters].any? {|param| param[:type] == 'File'}
              operation[:consumes] = %w(multipart/form-data)
            end
            operation[:responseMessages] = http_codes if http_codes.present?

            if route.route_entity
              operation['type'] = parse_entity_name(Array(route.route_entity).first)
            end

            operation
          end.compact

          {path: path, operations: operations}
        end

        models |= models_with_included_presenters(models.to_a)

        # use custom resource naming if available
        api_description = {
            apiVersion:     api_version,
            swaggerVersion: '1.2',
            resourcePath:   resource_path,
            produces:       content_types,
            apis:           apis
        }

        base_path                        = parse_base_path(request)
        api_description[:basePath]       = base_path if base_path && base_path.size > 0 && root_base_path != false
        api_description[:models]         = parse_entity_models(models.to_a) unless models.empty?
        api_description[:authorizations] = authorizations if authorizations

        api_description
      end

      def parse_entity_models(models)
        models.reduce({}) do |result, model|
          doc = GrapeSwagger::Documentation::ModelDoc.fetch(model, documentation_class)

          result[doc.name] = {
              id:         doc.id,
              properties: doc.properties
          }.tap do |h|
            required = doc.required_properties
            h[:required] = required if required.present?
          end

          result
        end
      end

      def parse_http_codes(codes)
        models = []
        hash = (codes || {}).map do |k, v, m|
          models << m if m
          http_code_hash = {
              code: k,
              message: v
          }
          http_code_hash[:responseModel] = parse_entity_name(m) if m
          http_code_hash
        end

        [hash, models]
      end

      def models_with_included_presenters(models)
        models.flatten.compact.flat_map do |model|

          # get model references from exposures with a documentation
          nested_models = model.exposures.map do |_, config|
            if config.key?(:documentation)
              model = config[:using]
              model.respond_to?(:constantize) ? model.constantize : model
            end
          end.compact

          # get all nested models recursively
          nested_models.flat_map do |nested_model|
            [nested_model] + models_with_included_presenters([nested_model])
          end
        end
      end

      def parse_base_path(request)
        if base_path.is_a?(Proc)
          base_path.call(request)
        elsif base_path.is_a?(String)
          URI(base_path).relative? ? URI.join(request.base_url, base_path).to_s : base_path
        else
          request.base_url
        end
      end

      def parse_path(path, version)
        # adapt format to swagger format
        parsed_path = path.gsub('(.:format)', documentation_class.hide_format? ? '' : '.{format}')
        # This is attempting to emulate the behavior of
        # Rack::Mount::Strexp. We cannot use Strexp directly because
        # all it does is generate regular expressions for parsing URLs.
        # TODO: Implement a Racc tokenizer to properly generate the
        # parsed path.
        parsed_path = parsed_path.gsub(/:([a-zA-Z_]\w*)/, '{\1}')
        # add the version
        version ? parsed_path.gsub('{version}', version) : parsed_path
      end
    end
  end
end
