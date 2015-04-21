module GrapeSwagger
  class Documentation < Grape::API
    class APIDoc < BaseDoc
      delegate :extra_info, :hide_format?, :authorizations, :hide_documentation_path?, :mount_path, :api_version, :target_class, to: :documentation_class

      def description
        namespaces = endpoint.combined_namespaces
        namespace_routes = endpoint.combined_namespace_routes.each_with_object({}) do |(key, routes_with_endpoints), res|
          res[key] = routes_with_endpoints
        end

        if hide_documentation_path?
          namespace_routes.reject! { |route, _value| "/#{route}/".index(parse_path(mount_path, nil) << '/') == 0 }
        end

        namespace_routes_array = namespace_routes.keys.map do |local_route|
          next if namespace_routes[local_route].map(&:first).map(&:route_hidden).all? { |value| value.respond_to?(:call) ? value.call : value }

          url_format  = '.{format}' unless hide_format?

          original_namespace_name = endpoint.combined_namespace_identifiers.key?(local_route) ? endpoint.combined_namespace_identifiers[local_route] : local_route
          description = namespaces[original_namespace_name] && namespaces[original_namespace_name].options[:desc]
          description ||= "Operations about #{original_namespace_name.pluralize}"
          description = description.call if description.is_a?(Proc)

          {path: "/#{local_route}#{url_format}",
           description: description}
        end.compact

        output = {
            apiVersion:     api_version,
            swaggerVersion: '1.2',
            produces:       content_types_for(endpoint),
            apis:           namespace_routes_array,
            info:           parse_info(extra_info)
        }

        output[:authorizations] = authorizations unless authorizations.nil? || authorizations.empty?

        output
      end

      def content_types_for(target_class)
        content_types = (target_class.content_types || {}).values

        if content_types.empty?
          formats       = [target_class.format, target_class.default_format].compact.uniq
          formats       = Grape::Formatter::Base.formatters({}).keys if formats.empty?
          content_types = Grape::ContentTypes::CONTENT_TYPES.select { |content_type, _mime_type| formats.include? content_type }.values
        end

        content_types.uniq
      end

      def parse_info(info)
        translations = I18n.t(target_class.name.underscore.gsub('/', '.'), default: {}) || {}
        {contact:            info[:contact],
         description:        as_markdown(translations[:description] || info[:description]),
         license:            info[:license],
         licenseUrl:         info[:license_url],
         termsOfServiceUrl:  info[:terms_of_service_url],
         title:              translations[:title] || info[:title]
        }.delete_if { |_, value| value.blank? }
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

      def strip_heredoc(string)
        indent = string.scan(/^[ \t]*(?=\S)/).min.try(:size) || 0
        string.gsub(/^[ \t]{#{indent}}/, '')
      end
    end
  end
end