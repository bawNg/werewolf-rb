module Ripl
  class << self
    def start(*args)
      Runner.start(*args)
      EM.watch_stdin Readline::EmInput, args.last
    end
  end

  module Readline
    module Em
      def get_input
        history << @input unless @input.blank?
        @input
      end
    end

    module EmInput
      def initialize(opts = {})
        super()
        @on_exit = opts && opts[:on_exit] or proc { Core.exit }
        handler_install
        ::Ripl.shell.before_loop
      end

      def notify_readable
        ::Readline.callback_read_char
      end

      def handle_interrupt
        ::Readline.callback_handler_remove
        detach
      end
    end
  end

  class Shell
    def print_result(result)
      print(format_result(result) + "\n") unless @error_raised
    rescue StandardError, SyntaxError
      warn "Error: #{MESSAGES['print_result']}:\n"+ format_error($!)
    end

    def print_eval_error(ex)
      print "Exception raised: #{ex.message.gsub /\n/, ' '}\n"
      ex.backtrace.each {|line| print "#{line}\n" }
    end
  end

  class DRb
    attr_reader :result

    def initialize
      @original_stdout = $stdout
      @original_stderr = $stderr
    end

    def run(str)
      File.open('./script/console.output', 'w') do |f|
        $stdout = $stderr = f
        begin
          print "#{Object.send(:eval, str, TOPLEVEL_BINDING).inspect}\n"
        rescue Exception => ex
          print "Exception raised: #{ex.message.gsub /\n/, ' '}\n"
          ex.backtrace.each {|line| print "#{line}\n" }
        ensure
          $stdout = @original_stdout
          $stderr = @original_stderr
        end
      end
      @result = open('./script/console.output').read.chomp
    end
  end
end