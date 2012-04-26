require 'drb'
require './lib/inspected'
load 'helpers/general.rb'

module Modules
  EXTENDED_OUTPUT = false

  @modules = {}
  @depend_on = {}
  @monkeypatched = {}
  @origional_const = {}
  @last_exception = nil
  @loading_module = false
  @load_queue = []

  class << self
    attr_accessor :last_exception, :drb_server, :inspector, :loading_module

    def exist?(name)
      filename = (sub_path = name.underscore)[/([^\/]+)$/, 1]
      %W[ modules/#{sub_path}.rb modules/#{sub_path}/#{filename}.rb ].any? {|path| File.file? path }
    end

    def loaded?(name)
      @modules.include? name
    end

    def loaded
      @modules.keys
    end

    def count
      @modules.count
    end

    def each
      @modules.each {|key, value| yield key, value }
    end

    def collect
      @modules.collect
    end

    def unloadable
      @depend_on.values.flatten.uniq - loaded
    end

    def dependencies(name)
      @depend_on.select {|k, names| names.include? name }.keys
    end

    def needed_dependencies(name)
      dependencies(name) - loaded
    end

    def commands
      modules = @modules.reject {|name, mod| !defined?(mod::Commands) }
      commands = modules.collect {|name, mod| mod::Commands }
      Hash[*commands.collect {|h| h.to_a }.flatten]
    end

    def find_by_command(cmd)
      name, mod = @modules.detect {|name, mod| defined?(mod::Commands) and mod::Commands.include? cmd }
      mod
    end

    def find_name_by_command(cmd)
      name, mod = @modules.detect {|name, mod| defined?(mod::Commands) and mod::Commands.include? cmd }
      name
    end

    def class_name(name)
      split_path = name.underscore[/(?:modules\/)?([^\.]+)/, 1].split '/'
      split_path.delete_at -2 if split_path[-2] == split_path[-1]
      split_path.join('/').camelize
    end

    def fire_event(event, *args)
      each do |_, mod|
        next unless callbacks = mod.callbacks[event]
        callbacks.each {|callback| callback.call(*args) }
      end
    end

    def module_paths
      Dir['modules/**/*.rb'].reject do |path|
        path =~ /\/(lib|helpers)\/.+\.rb$/
      end
    end

    def load(name)
      return inspector_has_started { load(name) } unless inspector_loaded?
      load_module(name) do |loaded|
        puts "Loaded module: #{name}" if loaded
        yield loaded if block_given?
      end
    end

    def unload(name)
      unloaded = unload_module(name)
      puts "Unloaded module: #{name}" if unloaded
      unloaded
    end

    def reload(name)
      return inspector_has_started { reload(name) } unless inspector_loaded?
      unload_module(name)
      load_module(name) do |loaded|
        puts "Reloaded module: #{name}" if loaded
        yield loaded if block_given?
      end
    end

    def reload_by_command(command)
      @modules.values.each do |mod|
        next unless defined? mod::Commands
        next unless mod::Commands.include? command
        reload(mod.name)
      end
    end

    def load_all
      puts "Loading modules..."
      module_paths.each do |path|
        load class_name(path)
      end
    end

    def unload_all
      puts "Unloading all modules..."
      @modules.each do |name, mod|
        unload_module(name)
      end
    end

    def inspector_loaded?
      unless inspector
        start_inspector
        return false
      end
      true
    end

    def load_module(name, options={}, callback=nil, &block)
      callback ||= block
      return @load_queue << [name, options, callback] if @loading_module

      puts "Loading module: #{name}" if EXTENDED_OUTPUT
      @loading_module = true
      sub_path = name.underscore
      module_path = "modules/#{sub_path}"
      unless File.file? "modules/#{sub_path}.rb"
        file_name = File.basename(sub_path)
        #puts "sub module path for #{name}: modules/#{sub_path}/#{file_name}.rb"
        sub_path << "/#{file_name}" if File.file? "modules/#{sub_path}/#{file_name}.rb"
      end
      file_path = "modules/#{sub_path}.rb"

      puts "Inspecting module..." if EXTENDED_OUTPUT
      inspect_all do |inspected_modules|
        puts "Parsing module..." if EXTENDED_OUTPUT
        parser = Parser.parse(file_path)
        puts "Checking dependencies..." if EXTENDED_OUTPUT
        needed_dependencies = []
        parser.all_constants.each do |const_name| # All constants referenced to
          next if const_name.underscore == name.underscore

          inspected_modules.each do |module_name, inspected|
            next if module_name == name
            next unless inspected.constant_names.include? const_name

            @depend_on[module_name] ||= []
            @depend_on[module_name] << name unless @depend_on[module_name].include? name
            needed_dependencies << module_name unless loaded? module_name
          end
        end

        if needed_dependencies.present?
          puts "#{name} requires dependent modules to load: #{needed_dependencies.to_sentence}"
          @last_exception = RuntimeError.new "Requires modules to load: #{needed_dependencies.to_sentence}"
          @loading_module = false
          callback.(false) if callback
          load_module(*@load_queue.shift) if @load_queue.size > 0
          return
        end

        parser.all_constants.each do |const_name| # All constants referenced to
          if const_name.starts_with? '::'
            # Is a top level constant
            const_name = const_name[2..-1]
            if inspected_modules[name].constant_names.include? const_name #TODO: replace constant_names with something containing all defined constants, including top level ones
              # Constant is defined in this module
              puts "[load_module] Storing backup copy of #{const_name}"
              # Store origional value for constant before it is monkeypatched
              (@monkeypatched[name] ||= []) << const_name
              @origional_const[const_name] = const_name.constantize.dup
            end
          end
        end

        receiver = get_namespace(name, inspected_modules[name])

        #TODO: enable for all classes and modules (move out of get_namespace)
        unless inspected_const = inspected_modules[name].constants.detect {|const| const.name == name }
          puts "Unable to find inspected const #{name.inspect} in: #{inspected_modules[name].constants.collect(&:name).inspect}"
        end

        klass = inspected_const.class_name.constantize

        superclass = Object
        if inspected_const.superclass_name #TODO: use name when exists, else namespace?
          superclass = recursive_const_get(inspected_const.namespace, inspected_const.superclass_name)
        end

        puts "Building module..." if EXTENDED_OUTPUT
        mod = (klass == Class) ? klass.new(superclass) : klass.new
        puts "Including module base..." if EXTENDED_OUTPUT
        mod.send :include, Base
        puts "Setting module base attributes..." if EXTENDED_OUTPUT
        mod.name = name
        mod.const_set :MODULE_ROOT, module_path

        receiver.const_set(name.demodulize, mod)
        #puts "[load_module] Created #{inspected_const.class_name}: #{name} (#{inspected_const.superclass_name})"

        if Dir.exists? File.join(module_path, 'lib')
          puts "Loading module libraries..." if EXTENDED_OUTPUT
          Dir[File.join(module_path, 'lib', '*.rb')].each do |path|
            Kernel.load(path) #TODO: load library into module namespace instead of top level
            @inspector.load_module(path)
            top_constants = @inspector.top_constants
            mod.libraries += top_constants.collect(&:name)
          end
        end

        puts "Loading module helpers..." if EXTENDED_OUTPUT
        helper_paths = [File.join(module_path, 'helpers')] #TODO: allow more than one level lookback for helpers
        helper_paths << File.join(module_path[/(.+)\/[^\/]+/, 1], 'helpers') if name.include?('::')
        helper_paths.each do |helpers_path|
          if Dir.exists? helpers_path
            Dir[File.join(helpers_path, '*.rb')].each do |path|
              #puts "Loading helpers into #{mod.name}: #{path}"
              helpers = Module.new do
                def self.included(base)
                  base.extend self
                end
                binding.eval(File.read(path), path)
              end
              mod.send :include, helpers

              mod.libraries.each do |library_name|
                const_get(library_name).send :include, helpers
              end
            end
          end
        end

        puts "Loading module file..." if EXTENDED_OUTPUT
        Kernel.load(file_path)

        mod = name.constantize rescue raise(RuntimeError, "Cannot find module!")

        @modules[name] = mod

        EM.next_tick { module_loaded(mod) }

        @loading_module = false
        callback.(false) if callback
        load_module(*@load_queue.shift) if @load_queue.size > 0
      end
    rescue Exception => ex
      puts "Exception raised while loading module: #{name} (#{ex.class})"
      puts "Exception: #{ex.message.gsub(/\n/, ' ')}"
      ex.backtrace.each {|line| print line + "\n" }
      @last_exception = ex
      self.unload(name)
      callback.(false) if callback
    end

    def unload_module(name, options={})
      (mod = name.constantize) rescue return false

      if mod.constants.include? "Commands"
        Command.remove_handlers(mod::Commands.keys) if const_defined? :Command
      end

      #TODO: check for multiple modules in module file and not just "name"
      puts "[unload_module] Modules that require #{name}: #{@depend_on[name].to_sentence}" if @depend_on[name] unless $exiting
      @depend_on[name].each {|module_name| unload_module(module_name); @modules.delete(module_name) } if @depend_on[name]

      module_unloaded(mod)# unless options[:parent]

      #if mod.submodules.present?
      #  mod.submodules.each do |submodule|
      #    unload_submodule(submodule, mod)
      #    mod.submodules.delete(submodule)
      #  end
      #end

      mod.scheduler.remove_all if mod.respond_to? :scheduler

      mod.libraries.each {|const_name| Object.send :remove_const, const_name if Object.const_defined? const_name }

      receiver = get_namespace(name)
      receiver.send :remove_const, name.demodulize if receiver.const_defined? name.demodulize

      if @monkeypatched[name].present?
        @monkeypatched[name].each do |const_name|
          Kernel.const_set(const_name, @origional_const.delete(const_name))
          puts "[unload_module] Restored #{const_name} to origional state." unless $exiting
        end
        @monkeypatched.delete(name)
      end

      @modules.delete(name)
      true
    end

    def on(event, evaluator=self)
      return if evaluator.sender.nick.downcase == 'chanserv'
      each do |module_name, mod|
        next unless mod.callbacks
        next if (callbacks = mod.callbacks[event]).blank?
        evaluator.extend IrcHelpers
        evaluator.extend mod
        evaluator.class.send :attr_reader, :scheduler, :user, :game, :player
        evaluator.instance_variable_set :@scheduler, mod.scheduler
        evaluator.instance_variable_set :@user, user = User[evaluator.sender.user.username] if evaluator.sender.user

        begin #TODO: refactor to irc module once an interface has been added
          game = nil
          Irc.servers.each do |_, server|
            next unless game = server.channels[server.channel][:game]
            next unless game.include? evaluator.sender
            break evaluator.instance_variable_set :@game, game
          end
          unless game
            Irc.servers.each do |_, server|
              next unless server.users(server.channel).include? evaluator.sender.nick
              next unless game = server.channels[server.channel][:game]
              break evaluator.instance_variable_set :@game, game
            end
          end
          evaluator.instance_variable_set :@player, game.find_player(evaluator.sender) if game and evaluator.sender
        rescue Exception => ex
          log :red, "Exception while building event evaluator: #{ex.message}"
          ex.backtrace.each {|line| print "#{line}\n".light_red }
        end

        callbacks.each do |callback|
          begin
            evaluator.instance_eval(&callback)
          rescue Exception => ex
            log_exception(ex, self.class)
          end
        end
      end
    end

    def connect_to_inspector(port)
      if !drb_server || !drb_server.alive?
        puts "Starting new DRb service..."
        self.drb_server = DRb.start_service
      end

      self.inspector = DRbObject.new(nil, "druby://127.0.0.1:#{port}")

      puts "Connected to inspector process on port #{port}."
      log_to_file(:inspector, "Connected to inspector process on port #{port}.")

      timer = EM.add_periodic_timer(0.5) do
        next timer.cancel if $exiting
        unless inspector
          #puts "[#{port}] No inspector to ping, #{'starting new inspector, ' unless @inspector_is_starting}cancelling ping timer..."
          start_inspector
          next timer.cancel
        end
        begin
          #puts "[#{port}] Sending ping to inspector..."
          log_to_file(:inspector, "[#{port}] Sending ping to inspector...")
          inspector.ping
        rescue DRb::DRbConnError
          puts "[#{port}] Connection to inspector process lost while sending: ping"
          log_to_file(:inspector, "[#{port}] Connection to inspector process lost while sending: ping")
          start_inspector
          next timer.cancel
        end
      end

      inspector_has_started
    end

    def inspector_has_started(&block)
      if block_given?
        (@inspector_has_started ||= []) << block
      else
        log_to_file(:inspector, "Inspector has started")
        if @inspector_has_started
          @inspector_has_started.reject! do |block|
            break false unless inspector
            block.call
            true
          end
        end
      end
    end

    def rescue_exceptions(mod, module_action=nil)
      begin
        yield mod
      rescue Exception => ex
        loading_text = module_action || "#{(mod.respond_to?(:loaded?) ? ('un' if mod.loaded?) : '[un]')}loading"
        puts "Exception raised while #{loading_text} module: #{mod.name}"
        puts "Exception: #{ex.message.gsub(/\n/, ' ')}"
        ex.backtrace.each {|line| print line + "\n" }
        @last_exception = ex
        self.unload(mod.name) if mod.respond_to?(:unloaded?) && mod.unloading?
      end
    end

    def popen(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      command = args.join(' ')
      EM.defer do
        Open3.popen3(command + ' 2>&1') do |stdin, stdout, _, wait_thr|
          stdin.print options[:stdin] if options[:stdin]
          stdin.close
          output = ''
          begin
            while line = stdout.readline
              EM.next_tick { yield line.strip } if block_given?
              sleep 0.025
            end
          rescue EOFError
          end
          status = wait_thr.value
          EM.next_tick { yield output, status } if block_given?
        end
      end
    end

    def start_inspector
      return if $exiting || @inspector_is_starting || inspector
      @inspector_is_starting = true
      puts "Spawning new inspector process..."
      inspector_port = -1
      popen('ruby ./script/inspector.rb') do |line, status| #TODO: move popen somewhere (not in a module obviously)
        if status
          puts "Inspector process on port #{inspector_port} ended"
          log_to_file(:inspector, "Inspector process on port #{inspector_port} ended")
          self.inspector = nil
          EM.add_timer(0.1) { start_inspector unless inspector }
        else
          @inspector_is_starting = false
          inspector_port = line[/:(\d+)$/, 1].to_i
          puts "Inspector: #{line.inspect}" if inspector_port < 1
          Modules.connect_to_inspector(inspector_port) if inspector_port > 0
        end
      end
    end

   private
    def inspect_module(filename)
      if inspector
        inspector.load_module filename
        yield
      else
        inspector_has_started do
          inspector.load_module filename
          yield
        end
        start_inspector
      end
    rescue DRb::DRbConnError
      puts "Connection to inspector has been lost"
      self.inspector = nil
      retry
    end

    def inspect_all
      modules = {}
      module_paths.each do |filename|
        name = class_name(filename)
        inspect_module(filename) do
          modules[name] = { 'constants' => @inspector.all_constants, 'constant_names' => @inspector.all_constant_names }
          if modules.size == module_paths.size
            modules.merge!(modules) do |name, inspected|
              # Remove any definited constants that belong to another module
              inspected.constant_names.reject! do |const_name|
                #TODO: check other modules const definitions? not only modules names
                modules.keys.reject {|class_name| class_name == name }.include? const_name
              end
              inspected
            end
            yield modules
          end
        end
      end
    end

    def get_namespace(name, inspected_module=nil)
      if name.include? '::'
        namespace = name[0..-(name.demodulize.size+3)]
        #TODO: check for undefined namespaces and define to allow nesting new namespaces in modules
        if inspected_module
          split_namespace = namespace.split '::'
          split_namespace.each.with_index do |const_name, i|
            scope = i > 0 ? split_namespace[0..i-1].join('::').constantize : Object
            unless scope.const_defined? const_name
              #TODO: move somewhere better
              inspected_const = inspected_module.constants.detect {|const| const.name == "#{scope.name}::#{const_name}" }
              puts "[get_namespace] Defining missing #{inspected_const.class_name}: #{scope.name}::#{const_name}"
              klass = inspected_const.class_name.constantize
              superclass = inspected_const.superclass_name ? inspected_const.superclass_name.constantize : Object
              scope.const_set(const_name, (klass == Class) ? klass.new(superclass) : klass.new)
            end
          end
        end
        namespace.constantize
      else
        Object
      end
    end

    def recursive_const_get(namespace, constant_name) #TODO: use qualified_const_get and #parents.reject {|klass| klass == Object }.last
      namespace = namespace.to_s unless namespace.is_a? String
      while namespace.present?
        scope = namespace.constantize
        constant_name.split('::').each do |const_name|
          unless scope.const_defined? const_name, false
            break scope = nil
          end
          scope = scope.const_get(const_name, false)
        end
        return scope if scope
        break unless namespace.gsub! /::[^:]+$/, ''
      end
      constant_name.constantize
    end

    def module_loaded(mod) #TODO: provide block callback for module load/reload methods which fire after all depending modules have been loaded
      @depend_on[mod.name].each do |module_name|
        load_module(module_name) unless @modules[module_name]
      end if @depend_on[mod.name]
      rescue_exceptions(mod, &:loaded) if mod.respond_to? :loaded
      rescue_exceptions(mod) {|m| m.callbacks[:loaded].each(&:call) if m.callbacks[:loaded] }
      mod.loaded = true if mod.class == Module
    end

    def module_unloaded(mod)
      #mod.submodules.each {|submodule| rescue_exceptions(submodule, &:pre_unload) if submodule.respond_to? :pre_unload }
      mod.unloading = true if mod.respond_to? :unloading=
      rescue_exceptions(mod, &:unloaded) if mod.respond_to? :unloaded
      rescue_exceptions(mod) {|m| m.callbacks[:unloaded].each(&:call) if m.callbacks[:unloaded] }
      # Remove module callbacks registered to this module
      each do |_, this_mod|
        this_mod.callbacks.each do |event_name, callbacks|
          callbacks.reject! {|callback| callback.binding.eval('name') == mod.name }
        end
      end
      mod.unloading = false if mod.respond_to? :unloading=
      #mod.submodules.each {|submodule| rescue_exceptions(submodule, &:unloaded) if submodule.respond_to? :unloaded }
    end
  end

  module Base
    def self.included(base)
      base.extend ClassMethods
      base.instance_variable_set :@callbacks, {}
      base.instance_variable_set :@command_restrictions, {}
      base.instance_variable_set :@models, []
      base.instance_variable_set :@libraries, []
      base.instance_variable_set :@attached_connections, [] # EM.watch connections
      base.instance_variable_set :@scheduler, Scheduler.new
    end

    module ClassMethods
      attr_accessor :name, :loaded, :unloading, :callbacks, :command_restrictions, :models, :libraries,
                    :attached_connections, :scheduler

      alias_method :loaded?,    :loaded
      alias_method :unloading?, :unloading
      alias_method :timer,      :scheduler
      alias_method :to_s,       :name

      include GeneralHelpers

      def config
        cfg = $config
        name.split('::').each do |mod_name|
          cfg = cfg[mod_name.underscore]
          break unless cfg
        end
        cfg
      end

      def on(event, *args, &block)
        if block_given?
          block = args.pop if args.last.is_a?(Proc) unless block_given?
          (callbacks[event] ||= []) << block
        else
          callbacks[event].each {|callback| callback.call(*args) } if callbacks[event]
        end
      end

      def model(*model_names)
        #puts "[model] adding models to #@name's models: #{model_names.inspect} (#{self.object_id})'"
        @models += model_names
      end

      #def const_missing(const_name)
      #  puts "[#{name}] const_missing: #{const_name} - #{@models.inspect} (#{self.object_id})"
      #  @models.each do |model_name|
      #    klass = model_name.to_s.constantize
      #    return klass.const_get(const_name) if klass.constants.include? const_name
      #  end
      #  super
      #end

      def send_cmd(*args)
        server_name = args.shift if args.first.is_a?(Symbol) and Core.irc.servers.include? args.first
        command = args.shift
        if server_name and server = Core.irc.servers[server_name]
          server.send_cmd(method_name, command, *args)
        else
          Core.irc.servers.each {|name, server| server.send_cmd(command, *args) }
        end
      end

      [:privmsg, :notice].each do |method_name|
        define_method(method_name) do |*args|
          server_name = args.shift if args.first.is_a?(Symbol) and Core.irc.servers.include? args.first
          target = args.shift if args.length > 1
          message = (args.shift || " ").to_irc
          if server_name and server = Core.irc.servers[server_name]
            server.send_cmd(method_name, target || server.channel, message)
          else
            Core.irc.servers.each {|name, server| server.send_cmd(method_name, target || server.channel, message) }
          end
        end
      end

      def send_to_channel(*args)
        server_name = args.shift if args.first.is_a?(Symbol) and Core.irc.servers.include? args.first
        target = args.shift if args.length > 1
        message = (args.shift || " ").to_irc
        return privmsg(message) unless server_name
        privmsg server_name, server.channel, message
      end

      def commands_available_in(channels, options={})
        # Apply restrictions to development channel when in development mode
        channels = Array.wrap(channels).collect {|channel| ARGV.first || channel }
        restrictions = { :channels => channels, :servers => Array.wrap(options[:on]) }
        commands = Array.wrap(options[:only] || const_get(:Commands).keys)
        commands -= except = Array.wrap(options[:except])
        @command_restrictions.reject! do |command, restricts|
          next if options[:on] unless restricts[:servers].include? options[:on]
          next unless channels.any? {|channel| restricts[:channels].include? channel }
          next true if options[:only] unless commands.include? command
          except.include? command
        end
        commands.each do |command|
          (@command_restrictions[command] ||= {}).merge! restrictions
        end
        #TODO: implement better functionality for instance usage
      end

      def rescue_exceptions(action='executing', &block)
        Modules.rescue_exceptions(self, action) { block.call(self) }
      end

      def next_tick(action='executing', &block)
        EM.next_tick { rescue_exceptions(action) { block.call } }
      end
    end

    include ClassMethods
  end

  class Parser < Ripper::SexpBuilder
    attr_reader :all_constants, :parsing_constants, :top_constant

    def self.parse(file_path, inspected_module=nil)
      self.new(IO.read(file_path)).tap do |builder|
        builder.instance_variable_set :@inspected_module, inspected_module
        builder.parse
      end
    end

    %w[ semicolon sp nl ].each do |event|
      define_method('on_' + event) do |*args|
        @expecting_const = false
        args
      end
    end

    def on_op(operator)
      #puts "[on_op] #{operator}"
      @expecting_const = true if operator == '::'
      operator
    end

    def on_symbeg(char)
      @expecting_symbol = true
      char
    end

    def on_symbol(*args)
      @expecting_symbol = false
      args
    end

    def on_const(const)
      expecting_const, @expecting_const = @expecting_const, false
      return const if @expecting_symbol

      #puts "[on_const] #{const} (expecting? #{expecting_const}) parsing: #{@parsing_constants.inspect}"

      while @parsing_constants.present?
        break if @parsing_constants.first == @top_constant
        #puts "Adding #{@parsing_constants.first} to parsed consts (#{@parsing_constants.first.inspect} != #{@top_constant})"
        constant_name = @parsing_constants.shift
        @all_constants ||= []
        @all_constants << constant_name unless @all_constants.include? constant_name
      end

      #puts "[on_const] #{const} (parsing_consts present? #{@parsing_constants.present?})"

      const_name = "#{'::' if expecting_const unless @parsing_constants.present?}#{const}"
      @top_constant = const if expecting_const unless @parsing_constants.present?

      (@parsing_constants ||= []) << const_name
      const_name
    end

    def on_const_path_ref(path, const)
      #puts "[on_const_path_ref] #{path} => #{const} (#{@top_constant})"

      if @parsing_constants.present?
        if @top_constant && @top_constant != path[1]
          @parsing_constants.clear
        end
      end

      full_constant_name = [*path[1..-1], const].join
      @top_constant = path[1]
      @all_constants ||= []

      unless path[1].is_a? Array
        @all_constants << @top_constant if path.length == 2 unless @all_constants.include? @top_constant
        @all_constants << full_constant_name unless @all_constants.include? full_constant_name
      end

      [*path, const]
    end

    def on_program(*args)
      return args if @all_constants.present? && @parsing_constants == @all_constants.last[0]
      #puts "[on_program] Appending last parsed consts: #{@parsing_constants.inspect}"
      @all_constants ||= []
      @all_constants += @parsing_constants if @parsing_constants.present?
      @all_constants.uniq!
    end
  end
end