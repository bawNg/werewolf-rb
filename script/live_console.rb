#!/usr/bin/env ruby

require 'drb'
require 'readline'
require 'wirb'

class Client
	def initialize
    if File.exists? './script/console.history'
      File.read('./script/console.history').split("\n").each {|line| Readline::HISTORY << line }
    end
		@repl = DRbObject.new nil, 'druby://:19234'
	end

	def run
    Readline.completion_append_character = ""
    Readline.completion_proc = proc do |str|
      if str =~ /\b([A-Z]\S+)\.(\S+)?/
        object_name = $1
        result = remote_exec("#{object_name}.public_methods")
        matching = result.start_with?('Exception raised:') ? [] : eval(result)
        matching = matching.grep /^#{$2 ? Regexp.escape($2) : '[^_]'}/
        matching.collect {|method_name| "#{object_name}.#{method_name}" }
      else
        matching = eval(remote_exec('Object.constants'))
        matching.grep /^#{Regexp.escape(str)}/
      end
    end

    while line = Readline.readline('>> ', true)
      next if line.nil?
      if line =~ /^\s*$/ || Readline::HISTORY.to_a[-2] == line
        Readline::HISTORY.pop
        next if line =~ /^\s*$/
      end
      open('./script/console.history', 'w') {|f| f << Readline::HISTORY.to_a.last(500).join("\n") }
      result = remote_exec(line)
      puts "=> #{colorize_result(result)}"
    end
  end

  def remote_exec(expression)
    begin
      @repl.run(expression)
      @repl.result
    rescue DRb::DRbConnError
      puts "Server disconnected"
      exit
    rescue Exception => e
      warn "#{e.class}: #{e.message}"
      puts e.backtrace if e.backtrace
    end
  end

  def colorize_result(result)
    Wirb.start unless Wirb.running?
    Wirb.colorize_result(result, Wirb.schema)
  end
end

begin
	Client.new.run
rescue SystemExit
	exit
rescue Interrupt
	puts
	exit
end