class Command
  class Callback
    def initialize(command, block)
      @command, @block = command, block
    end

    def call(event)
      CallbackDSL.run(event, @block)
    end

    module CallbackDSL
      def self.run(event, block)
        mod = Modules.find_by_command(event.command)
        klass = Class.new
        klass.send(:define_method, :scheduler) { mod ? mod.scheduler : Scheduler }
        if mod
          klass.send(:include, mod)
          mod.requires.each do |name|
            module_name = name.to_s
            if module_exists? module_name
              klass.send(:include, module_name.constantize)
            else
              puts "[#{mod.name}] Unable to include required module: #{module_name}"
            end
          end
        end
        klass.send(:include, self)
        callbackdsl = klass.new(event)
        begin
          block.arity < 1 ? callbackdsl.instance_eval(&block) : block.call(callbackdsl)
        rescue ArgError => ex
          callbackdsl.send_reply(*(callbackdsl.error_msgs ? callbackdsl.error_msgs : [ex.message]))
        rescue CommandError
        rescue NotImplementedError
          callbackdsl.send_reply 'Command not yet implemented!'
        end
      end

      attr_reader :info_board

      def initialize(event)
        @event = event
        @info_board = InfoBoard.new ->(line) { send_reply(event.channel? ? :notice : :privmsg, line) }
        load 'helpers/general.rb' if $development
      end

      load 'helpers/general.rb'
      include GeneralHelpers

      load 'helpers/irc.rb'
      include IrcHelpers

      def send_cmd(cmd, *args)
        @event.server.send_cmd(cmd, *args)
      end

      def send_to_origin(*msgs)
        return send_to_channel(*msgs) if @event.channel?
        send_reply(*msgs)
      end

      def method_missing(method, *args)
        method = method.to_s[0, method.to_s.size-1].to_sym if method.to_s[-1] == '?' unless @event.respond_to? method
        if @event.respond_to? method
          return @event.send(method, *args)
        elsif block_given? and (method_name = method.to_s).starts_with? 'when_'
          if index = @required_parameters.index(method_name[5..-1].downcase)
            return (yield if @event.all_params[index] == args.first.to_s.downcase)
          end
        end
        super
      end
    end
  end
end