module Thin
  module Backends
    class Base
       def stop
        @running  = false
        @stopping = true

        disconnect
        @stopping = false

        @connections.each {|connection| connection.close_connection }
        close
      end
    end
  end

  class Connection
    def handle_error
      log "[Thin] Unexpected error while processing request: #{$!.message}"
      $@.each {|line| log line }
      log_error
      close_connection rescue nil
    end
  end
end                                     #TODO: log exceptions