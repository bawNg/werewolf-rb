module Bitly
  @instance = new('defirence', 'R_9a545c541eef94278cf7af0975de8a32')

  class << self
    def shorten(*args)
      @instance.shorten(*args)
    rescue Exception => ex
      warn "[Bitly] Shorten failed, retrying... Exception message: #{ex.message}"
      begin
        @instance.shorten(*args)
      rescue Exception => ex
        warn "[Bitly] Shorten failed again, returning nil... Exception message: #{ex.message}"
        Struct.new(:jmp_url).new(args.first)
      end
    end

    def method_missing(method, *args)
      if @instance.respond_to? method
        @instance.send(method, *args)
      else
        super
      end
    end
  end
end