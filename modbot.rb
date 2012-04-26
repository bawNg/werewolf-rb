#!/usr/bin/env ruby
# encoding: utf-8

require 'bundler/setup'
Bundler.require

require 'active_support/core_ext'
require 'yaml'
require 'logger'
require 'ripper'
require 'readline'
require 'pp'

Dir['./lib/*.rb'].each {|path| require(path) }

require './helpers/text_helper'
require './model'
require './timers'
require './modules'

YAML::ENGINE.yamler = 'syck'

=begin # colour meanings
default
red            # error
green          # status
yellow         # debug
blue           # too dark
magenta        # received from irc
cyan           # user account
light_red      # exception backtrace
light_green    # status info?
light_yellow
light_blue     # sending to irc
light_magenta  # dependency
light_cyan
light_white

String.colors.each {|colour| print "#{colour}\n".colorize(colour) }
=end

module Core
  attr_reader :time_started

  class << self # class attributes
    def exit(msg="Shutting down")
      return if $exiting
      log :green, "#{msg}..."
      $exiting = true
      Modules.unload_all
      EM.add_timer(0.25) { EM.stop }
    end

    def restart(msg="Reloading core")
      log :green, "#{msg}..."
      Modules.unload_all
      EM.add_timer(0.25) do
        EM.stop
        system 'ruby', $0, *ARGV
      end
    end
  end

  trap('INT') { exit }
  trap('QUIT') { exit }

  Name    = "ModBot"
  Version = "0.1 BETA"

  $identifier  = ARGV.detect {|arg| !arg.starts_with? '#' }
  $prefix      = $identifier + '_' if $identifier
  $dev_channel = ARGV.detect {|arg| arg.starts_with? '#' }
  $development = !!$dev_channel
  $debug       = false

  @time_started = Time.now

  log :green, "Loading #{Name} v#{Version}..."
  log :green, "Loading YAML config..."
  $config = Hash[YAML.load_file("config.yml").collect {|k, v| [k, v] }]
  log :green, "Loaded config: #{$config.inspect}"

  $template = YAML.load_file("#{$prefix}template.yml")
  log :green, "Loaded template file."

  $config.databases.each do |config|
    case config.adapter
      when 'sqlite3'
        config.database = "./db/#{config.database}.sqlite3"
      else
        raise NotImplementedError, "Database adapter not supported: #{config.adapter}"
    end
    ActiveRecord::Base.establish_connection(config)
  end

  Model.load_all

  puts "#{Name} v#{Version} loaded."

  #EM.error_handler do |ex|
  #  puts "Exception raised during callback: #{ex.message.gsub(/\n/, ' ')}"
  #  ex.backtrace.each {|line| print line + "\n" }
  #end

  EM.epoll
  EM.run do
    Modules.load_all
    DRb.start_service 'druby://:19234', Ripl::DRb.new
    Ripl.start on_exit: method(:exit)
  end
end
