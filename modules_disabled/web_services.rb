require 'sinatra/base'
require 'sinatra/async'
require 'sinatra/flash'
require 'rack/methodoverride'
require 'sinatra/flash'
require 'haml'
require 'action_view'

module WebServices
  @routes = {}
  @reload = true

  class << self
    attr_reader :routes, :reload

    def loaded
      log "Starting Thin on port #{config.port.inspect}..."
      @server = Thin::Server.new('0.0.0.0', config.port + (ARGV.first ? 1 : 0), signals: false) do
        #use Rack::CommonLogger

        map '/' do
          run Router.new
        end
      end
      @server.timeout = 1800 # for long polling
      next_tick { @server.start }
    end

    def unloaded
      Modules.rescue_exceptions(self) { @server.stop if @server and @server.running? }
    end

    def map(new_mappings)
      new_mappings.merge!(new_mappings) {|key, routes| Array.wrap(routes) }
      @routes.merge! new_mappings do |key, old_routes, new_routes|
        (old_routes + new_routes).uniq
      end
      #puts "[map] #{@routes.inspect}"
    end

    def reload?(name)
      module_name = name.starts_with?('WebServices::') ? name.slice(0..12) : name
      reload.is_a?(Array) ? reload.include?(module_name) : reload
    end
  end

  class Router
    def call(env)
      path = env['PATH_INFO'].dup
      full_path = env['PATH_INFO'].dup

      until WebServices.routes.has_key? path
        path = path.rpartition('/').first # Chop off nested directories until we have a hit
        break path = '/' if path.empty?   # path is empty, in which case, default to root
      end

      response = [404, {}, []]
      return response unless WebServices.routes[path]

      env['PATH_INFO'] = env['PATH_INFO'][path.size..-1]

      #puts "[WebServices::Router] Routing: #{path}"
      WebServices.routes[path].each do |class_name|
        class_name.insert 0, "WebServices::" unless class_name.starts_with? "WebServices::"
        scope = class_name[0..-(class_name.demodulize.size+3)].constantize

        full_path.slice! -1 if full_path.ends_with?('/') unless path.ends_with? '/'

        if scope.const_defined? class_name.demodulize
          if env['REQUEST_METHOD'] == 'GET' and path == full_path || env['PATH_INFO'] == '/admin' # index or /admin - #TODO: add helper to modules to specify paths to reload
            #puts "path(#{path}) == full_path(#{full_path})"
            if WebServices.reload? class_name
              unless Modules.reload(class_name)
                return [200, {}, [class_name + ' failed to reload: ' + Modules.last_exception.message]]
              end
            end
          end
        elsif Modules.exist?(class_name)
          unless Modules.load(class_name)
            response = [200, {}, [class_name + ' failed to reload: ' + Modules.last_exception.message]]
            next puts "[WebServices::Router] (#{full_path}) Class does not exist: " + class_name
          end
        end

        #TODO: test if its possible that module references to models are outdated after reloading the model after the module has been loaded
        klass = class_name.constantize
        if env['REQUEST_METHOD'] == 'GET' and path == full_path || env['PATH_INFO'] == '/admin' # index or /admin
          puts "Reloading models: #{full_path}" if WebServices.reload? class_name
          klass.models.each {|model| Model.reload(model.to_s) } if WebServices.reload? class_name
        end
        response = klass.new.call(env)
        break unless response[0] == 404
      end
      #puts "[WebServices::Router] Responding with: #{response[0..1].inspect}"

      response
    end
  end

  module Sinatra
    class Base < ::Sinatra::Base
      register ::Sinatra::Async

      use Rack::MethodOverride

      #enable :dump_errors

      mime_type :coffee, 'text/coffeescript'

      class << self
        def enable_sessions(options)
          use Rack::Session::Cookie, options.reverse_merge(:secret => '64m353rv3rc00k13')
        end

        def cache
          @cache ||= {}
        end

        def async_connections
          @async_connections ||= []
        end

        def last_async_update_at

        end

        def send_async_update(data) # remove redundant dup
          async_connections.dup.each do |request|
            request.body data.to_json
          end
        end

        def partial(name, locals={})
          template = File.read("#{settings.root}/views/_#{name}.haml")
          Haml::Engine.new(template).render(Object.new, locals)
        end
      end

      helpers do
        def scheduler
          puts "[#scheduler] #{self.class.inspect}: #{self.class.scheduler.inspect if self.class.respond_to? :scheduler}"
          self.class.scheduler
        end

        def cache
          self.class.cache
        end

        def async_connections
          self.class.async_connections
        end

        def send_aync_update(data)
          self.class.send_async_update(data)
        end

        def json_body(data)
          content_type 'text/javascript'
          body data.to_json
        end

        def partial(template, *args)
          template_array = template.to_s.split('/')
          template = template_array[0..-2].join('/') + "/_#{template_array[-1]}"
          options = args.last.is_a?(Hash) ? args.pop : {}
          options.merge!(:layout => false)
          if collection = options.delete(:collection) then
            collection.inject([]) do |buffer, member|
              buffer << haml(:"#{template}", options.merge(:layout =>
              false, :locals => {template_array[-1].to_sym => member}))
            end.join("\n")
          else
            haml(:"#{template}", options)
          end
        rescue Exception => ex
          log_exception(ex, "rendering #{template} partial")
        end

        def content_for(key, *args, &block)
          @sections ||= Hash.new {|k,v| k[v] = [] }
          if block_given?
            @sections[key] << block
          else
            @sections[key].inject('') {|content, block| content << block.call(*args) } if @sections.keys.include? key
          end
        end
      end
    end
  end
end
