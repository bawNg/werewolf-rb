class Module
  def self.to_class
    Class.new.extend(self)
  end
end