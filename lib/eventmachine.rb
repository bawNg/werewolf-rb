module EventMachine
  module UncrashableDeferrable
    include Deferrable
    def set_deferred_status(status, *args)
      super
    rescue Exception => ex
      puts "[#{self.class}] Exception caught in callback: #{ex.message}"
      File.open('log/exception.log', 'a') do |file|
        file.puts "[#{Time.now.strftime "%a %d %B %Y %I:%M:%S %p"}] Exception caught in callback: #{ex.message}"
        ex.backtrace.each do |line|
          puts line
          file.puts line.sub(File.dirname($0), '.')
        end
        file.puts
      end
    end
  end

  class HttpRequest
    include UncrashableDeferrable
  end

  class MultiRequest
    include UncrashableDeferrable
  end

  self.threadpool_size = 30

  class << self
    def queued_threads
      @threadqueue.try(:size)
    end

    def process_ended(pid, partial_name=nil, &block)
      timer = PeriodicTimer.new(0.5) do
        unless Process.exists?(pid, partial_name)
          block.call(pid)
          timer.cancel
        end
      end
    end

    def wait_for_callbacks
      obj = Module.new do  #TODO: refactor to static module
        @remaining = 0

        def self.callbacks
          @callbacks ||= []
        end

        def self.queue(*args)
          @remaining += 1
          proc do |*block_args|
            callbacks << args + block_args
            callback if (@remaining -= 1) == 0
          end
        end

        def self.callback(&block)
          if block_given?
            @callback = block
            return if @remaining > 0
          end
          if EM.reactor_thread?
            @callback.(self)
          else
            next_tick { @callback.(self) }
          end
        end
      end
      yield obj
      obj
    end

    def defer_now(op = nil, callback = nil, &blk)
      unless @threadpool
        @threadpool = []
        @threadqueue = ::Queue.new
        @resultqueue = ::Queue.new
        spawn_threadpool
      end

      @threadqueue.unshift [op||blk,callback]
    end
  end
end
#TODO: rescue and handle permission error exceptions for file operations (https://github.com/jordansissel/eventmachine-tail/blob/master/lib/em/filetail.rb)