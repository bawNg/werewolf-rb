#!/usr/bin/env ruby

require 'active_support/core_ext'
require 'drb'
require 'pp'
require './lib/inspected'

$stdout.sync = $stderr.sync = true

module StubbedModule
  def require(*args) end
  #def const_missing(const, *args); puts "Const called: #{const} with args: #{args.inspect}"; Class.new end
  def method_missing(method, *args)
    #puts "(#{self.class.name}: #{self}) Method called: #{method.inspect}"
    return super if method.to_s.start_with? 'to_'
    #puts "[Inspector] (#{self.class.name}: #{self}) Method called: #{method.inspect}"
    klass = Class.new
    def klass.stubbed?; true end
    klass
  end
end

class Module
  include StubbedModule
  def const_missing(const)
    namespace = instance_variable_get(:@real_name) || name
    const_name = "#{namespace + '::' if namespace unless const.starts_with?(namespace)}#{const}"
    #puts "[Inspector] Const called: #{const_name}"
    klass = Class.new
    klass.send(:define_method, :initialize) {|*args| }
    klass.send(:instance_variable_set, :@real_name, const_name)
    klass.send(:attr_reader, :real_name)
    def klass.stubbed?; true end
    def klass.inspect; @real_name end
    klass
  end
end

class Object; include StubbedModule end

module Inspector
  include DRbUndumped

  @top_level_constants = Module.constants
  @inspector_constants = constants
  @seen_constant       = {}

  class << self
    attr_reader :loaded_module, :requires

    def ping
      puts "[#{Time.now.strftime "%a %d %B %Y %I:%M:%S %p"}] Received: ping"
      $last_ping = Time.now
    end

    def load_module(path)
      $last_ping = Time.now
      puts "[Inspector] Loading module: #{path}"
      reset if @loaded_module
      source = IO.read(path)
      @requires = source.scan /^\s*require (.+)/
      source.gsub! /^\s*(require|include) .+/, '' #|extend
      module_eval(source, path)
      puts "[Inspector] Module loaded: #{path}"
      puts "[Inspector] Constants loaded: #{(constants - @inspector_constants).inspect}"
      @loaded_module = path
    rescue Exception => ex
      puts "Exception while loading #{path}: #{ex.message}"
      puts ex.backtrace
    end

    def reset
      $last_ping = Time.now
      (constants - @inspector_constants).each do |const|
        #puts "[Inspector#reset] Removing constant: #{const}"
        remove_const(const)
      end
      (Module.constants - @top_level_constants).each do |const|
        #puts "[Inspector#reset] Removing top level constant: #{const}"
        Object.send :remove_const, const
      end
      @seen_constant.clear
      @loaded_module = nil
      puts "[Inspector] Reset"
    end

    def all_constant_names(constant=self)
      $last_ping = Time.now
      constants =
          constant.constants.collect do |const_name|
            #puts "#{"[#{constant}] " unless constant == self}constant_name: #{const_name}"
            const = constant.const_get(const_name)
            if @seen_constant[const] || !const.respond_to?(:constants)
              @seen_constant[const] = true
              next "#{constant.name.sub(/^Inspector::/, '') + '::' unless constant == self}#{const_name}"
            end
            @seen_constant[const] = true
            all_constant_names(const)
          end
      #puts "adding: #{constant.name}" unless constant == self
      constants << constant.name.sub(/^Inspector::/, '') unless constant == self
      p constants
      constants.flatten.uniq
    end

    def top_constants(constant=self)
      $last_ping = Time.now
      constant.constants.collect do |const_name|
        const = constant.const_get(const_name)
        super_class = const.respond_to?(:superclass) ? const.superclass.inspect : nil
        inspected_const = InspectedConstant.new(const.class.name, const_name, super_class)
        if const.respond_to? :constants
          nested_consts = top_constants(const)
          if nested_consts.present?
            inspected_const.constants = nested_consts
          end
        end
        inspected_const
      end
    end

    def all_constants
      $last_ping = Time.now
      all_constant_names.collect do |name|
        const = "Inspector::#{name}".constantize
        super_class = const.respond_to?(:superclass) ? const.superclass.inspect : nil
        InspectedConstant.new(const.class.name, name, super_class)
      end
    rescue Exception => ex
      puts "Exception while loading #@loaded_module: #{ex.message}"
      puts ex.backtrace
    end

    def modules
      top_constants.select {|const| const.class_name == 'Module' }
    end

    def classes
      top_constants.select {|const| const.class_name == 'Class' }
    end
  end
end

if $0 == __FILE__
  DRb.start_service nil, Inspector
  puts "[Inspector] Service started: #{DRb.uri}"

  $stdout = $stderr = open('./inspector.log', 'w')
  $stdout.sync = true

  $last_ping = Time.now

  loop do
    if Time.now - $last_ping > 4
      puts "[Inspector] Connection to parent has timed out"
      exit
    end
    sleep 0.5
  end
end