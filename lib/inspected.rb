module Inspected
  attr_accessor :constants, :class_name, :name, :superclass_name

  def initialize(klass, name, superclass)
    @class_name       = klass
    @name             = name
    @superclass_name  = superclass
    @constants        = []
  end

  def modules
    constants.select {|const| const.class_name == 'Module' }
  end

  def classes
    constants.select {|const| const.class_name == 'Class' }
  end

  def inspect
    data = {}
    data[:constants] = @constants if @constants.present?
    data[:superclass] = @superclass_name if @superclass_name
    return { class_name => name } unless data.present?
    "(#{class_name} => #{name}: #{data.inspect})"
  end
end

class InspectedConstant
  include Inspected

  def namespace
    name[0..-(name.demodulize.size+3)]
  end
end

class InspectedModule
  include Inspected
end