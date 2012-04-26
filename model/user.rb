class User
  attr_accessor :username, :nickname

  def self.[](username)
    new(username: username, nickname: username)
  end

  def initialize(attributes)
    attributes.each {|key, value| update_attribute(key, value) }
  end

  def registered?
    true
  end

  alias_method :exists?, :registered?

  def access_level
    100
  end

  def gender
    :male
  end

  def password_hash
    'none'
  end

  def registered_servers
    %w(ShadowFire)
  end

  def identified_on
    [:ShadowFire]
  end

  def update_attribute(key, value)
    instance_variable_set("@#{key}", value)
  end
end