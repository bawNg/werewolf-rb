require 'active_record'

module ActiveRecord
  class Base
    class << self
      alias :old_connection :connection
      def connection
        self.verify_active_connections!
        old_connection
      end
    end
  end
end