require 'grape'
require 'grape-swagger/version'
require 'grape-swagger/errors'
require 'grape-swagger/documentation'
require 'grape-swagger/markdown'
require 'grape-swagger/markdown/kramdown_adapter'
require 'grape-swagger/markdown/redcarpet_adapter'

module Grape
  class API
    class << self
      attr_reader :combined_routes, :combined_namespace_routes, :combined_namespace_identifiers

      def add_swagger_documentation(options = {})
        documentation_class = create_documentation_class

        documentation_class.setup({target_class: self}.merge(options))
        mount(documentation_class)

        @combined_routes = {}
        routes_with_endpoints.each do |endpoint, routes|
          routes.each do |route|
            route_path = route.route_path
            route_match = route_path.split(/^.*?#{route.route_prefix.to_s}/).last
            next unless route_match
            route_match = route_match.match('\/([\w|-]*?)[\.\/\(]') || route_match.match('\/([\w|-]*)$')
            next unless route_match
            resource = route_match.captures.first
            next if resource.empty?
            resource.downcase!
            combined_routes[resource] ||= []
            next if documentation_class.hide_documentation_path && route.route_path.include?(documentation_class.mount_path)
            combined_routes[resource] << [route, endpoint]
          end
        end

        @combined_namespace_routes = {}
        @combined_namespace_identifiers = {}
        combine_namespace_routes

        exclusive_route_keys = combined_routes.keys - combined_namespaces.keys
        exclusive_route_keys.each { |key| combined_namespace_routes[key] = combined_routes[key] }
        documentation_class
      end

      def routes_with_endpoints
        @routes_with_endpoints ||= endpoints.reduce({}) do |res, endpoint|
          res[endpoint] = endpoint.routes
          res
        end
      end

      def combined_namespaces
        @combined_namespaces ||= all_apps.reduce({}) do |combined_namespaces, app|
          app.endpoints.reduce(combined_namespaces) do |namespaces, endpoint|
            ns = if endpoint.respond_to?(:namespace_stackable)
                   endpoint.namespace_stackable(:namespace).last
                 else
                   endpoint.settings.stack.last[:namespace]
                 end
            # use the full namespace here (not the latest level only)
            # and strip leading slash
            namespaces[endpoint.namespace.sub(/^\//, '')] = ns if ns
            namespaces
          end
        end
      end

      private

      def all_apps(app = self)
        [app] + app.endpoints.flat_map {|e| e.options[:app] ? all_apps(e.options[:app]) : []}
      end

      def combine_namespace_routes
        # iterate over each single namespace
        combined_namespaces.each do |name, namespace|
          # get the parent route for the namespace
          parent_route_name = name.match(%r{^/?([^/]*).*$})[1]
          parent_route = combined_routes[parent_route_name]
          # fetch all routes that are within the current namespace
          namespace_routes = parent_route.map do |(route, endpoint)|
            [route, endpoint] if (route.route_path.start_with?("/#{name}") || route.route_path.start_with?("/:version/#{name}")) &&
                                 (route.instance_variable_get(:@options)[:namespace] == "/#{name}" || route.instance_variable_get(:@options)[:namespace] == "/:version/#{name}")
          end.compact

          if namespace.options.key?(:swagger) && namespace.options[:swagger][:nested] == false
            # Namespace shall appear as standalone resource, use specified name or use normalized path as name
            if namespace.options[:swagger].key?(:name)
              identifier = namespace.options[:swagger][:name].gsub(' ' , '-')
            else
              identifier = name.gsub('_', '-').gsub('/', '_')
            end
            @combined_namespace_identifiers[identifier] = name
            @combined_namespace_routes[identifier] = namespace_routes

            # get all nested namespaces below the current namespace
            sub_namespaces = standalone_sub_namespaces(name)
            # convert namespace to route names
            sub_ns_paths = sub_namespaces.collect { |ns_name, _| "/#{ns_name}" }
            sub_ns_paths_versioned = sub_namespaces.collect { |ns_name, _| "/:version/#{ns_name}" }
            # get the actual route definitions for the namespace path names
            sub_routes = parent_route.map do |(route, endpoint)|
              [route, endpoint] if sub_ns_paths.include?(route.instance_variable_get(:@options)[:namespace]) || sub_ns_paths_versioned.include?(route.instance_variable_get(:@options)[:namespace])
            end.compact
            # add all determined routes of the sub namespaces to standalone resource
            @combined_namespace_routes[identifier].push(*sub_routes)
          else
            # default case when not explicitly specified or nested == true
            standalone_namespaces = combined_namespaces.reject { |_, ns| !ns.options.key?(:swagger) || !ns.options[:swagger].key?(:nested) || ns.options[:swagger][:nested] != false }
            parent_standalone_namespaces = standalone_namespaces.reject { |ns_name, _| !name.start_with?(ns_name) }
            # add only to the main route if the namespace is not within any other namespace appearing as standalone resource
            if parent_standalone_namespaces.empty?
              # default option, append namespace methods to parent route
              @combined_namespace_routes[parent_route_name] ||= []
              @combined_namespace_routes[parent_route_name] += namespace_routes
            end
          end
        end
      end

      def standalone_sub_namespaces(name, namespaces = combined_namespaces)
        # assign all nested namespace routes to this resource, too
        # (unless they are assigned to another standalone namespace themselves)
        sub_namespaces = {}
        # fetch all namespaces that are children of the current namespace
        namespaces.each { |ns_name, ns| sub_namespaces[ns_name] = ns if ns_name.start_with?(name) && ns_name != name }
        # remove the sub namespaces if they are assigned to another standalone namespace themselves
        sub_namespaces.each do |sub_name, sub_ns|
          # skip if sub_ns is standalone, too
          next unless sub_ns.options.key?(:swagger) && sub_ns.options[:swagger][:nested] == false
          # remove all namespaces that are nested below this standalone sub_ns
          sub_namespaces.each { |sub_sub_name, _| sub_namespaces.delete(sub_sub_name) if sub_sub_name.start_with?(sub_name) }
        end
        sub_namespaces
      end

      def create_documentation_class
        Class.new(GrapeSwagger::Documentation)
      end
    end
  end
end
