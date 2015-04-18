require 'grape-swagger/documentation/base_doc'
require 'grape-swagger/documentation/api_doc'
require 'grape-swagger/documentation/endpoint_doc'
require 'grape-swagger/documentation/model_doc'

module GrapeSwagger
  class Documentation < Grape::API
    DEFAULTS = {
        target_class: nil,
        mount_path: '/swagger_doc',
        base_path: nil,
        api_version: '0.1',
        markdown: nil,
        hide_documentation_path: false,
        hide_format: false,
        format: nil,
        models: [],
        info: {},
        authorizations: nil,
        root_base_path: true,
        api_documentation: { desc: 'Swagger compatible API description' },
        specific_api_documentation: { desc: 'Swagger compatible API description for specific API' }
    }

    module Helpers
      def documentation_class
        options[:route_options][:api_class]
      end

      delegate :api_doc, :mount_path, to: :documentation_class
    end

    class << self
      attr_reader :target_class, :hide_documentation_path, :api_version, :authorizations, :models,
                  :root_base_path, :base_path, :extra_info, :api_doc, :specific_api_doc, :markdown

      def name
        @class_name || super
      end

      def hide_documentation_path?
        @hide_documentation_path
      end

      def mount_path
        @mount_path
      end

      def hide_format?
        @hide_format
      end

      def get(paths = ['/'], options = {})
        super(paths, options.merge(api_class: self))
      end

      def setup(options)
        options = GrapeSwagger::Documentation::DEFAULTS.merge(options)

        @target_class     = options[:target_class]
        @mount_path       = options[:mount_path]
        @class_name       = options[:class_name] || options[:mount_path].gsub('/', '')
        @markdown         = options[:markdown] ? GrapeSwagger::Markdown.new(options[:markdown]) : nil
        @hide_format      = options[:hide_format]
        @api_version      = options[:api_version]
        @authorizations   = options[:authorizations]
        @base_path        = options[:base_path]
        @root_base_path   = options[:root_base_path]
        @extra_info       = options[:info]
        @api_doc          = options[:api_documentation].dup
        @specific_api_doc = options[:specific_api_documentation].dup
        @models           = options[:models] || []

        @hide_documentation_path = options[:hide_documentation_path]

        if options[:format]
          [:format, :default_format, :default_error_formatter].each do |method|
            send(method, options[:format])
          end
        end

        helpers GrapeSwagger::Documentation::Helpers

        desc api_doc.delete(:desc), api_doc
        get mount_path do
          header['Access-Control-Allow-Origin']   = '*'
          header['Access-Control-Request-Method'] = '*'

          GrapeSwagger::Documentation::APIDoc.new(documentation_class).description
        end

        desc specific_api_doc.delete(:desc), { params: {
                                               'name' => {
                                                   desc: 'Resource name of mounted API',
                                                   type: 'string',
                                                   required: true
                                               }
                                           }.merge(specific_api_doc.delete(:params) || {}) }.merge(specific_api_doc)

        get "#{mount_path}/:name" do
          header['Access-Control-Allow-Origin']   = '*'
          header['Access-Control-Request-Method'] = '*'

          doc = GrapeSwagger::Documentation::EndpointDoc.new(documentation_class, params[:name])

          error!('Not Found', 404) unless doc.grouped_operations.present?

          doc.description(request)
        end
      end
    end
  end
end