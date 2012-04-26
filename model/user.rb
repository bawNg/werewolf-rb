class User < ActiveRecord::Base
  has_many :aliases, :class_name => 'Alias'
  has_many :user_attributes
  has_many :bans
  has_many :news                                             #TODO: replace caching with record-cache gem
  has_many :logs
  has_many :todos
  has_many :rss_feeds
  has_many :definitions

  # Attributes
  attr_accessor :identified_on, :nickname, :session_access_level

  # Filters
  after_initialize :init

  # Constants
  AccessLevel = { :banned => -1, :unregistered => 0, :registered => 1 }
  GenderPronoun = { :none => 'its', :male => 'his', :female => 'her' }
  GenderNoun = { :none => 'it', :male => 'he', :female => 'she' }
  Gender = { :none => 0, :male => 1, :female => 2 }

  class << self
    def cache
      @cache ||= {}
    end

    def get_gender(id)
      Gender.key(id)
    end

    def get_gender_pronoun(id)
      GenderPronoun[get_gender(id)]
    end

    def [](username)
      return cache[username.downcase] if cache.include? username.downcase
      user = where(:username => username).first || find_by_alias(username)
      return cache[username.downcase] = user if user
      User.new(:username => username, :access_level => 0).tap {|u| u.nickname = username }
    end

    def exists?(username)
      return super unless username.is_a? String
      exists?(:username => username) || Alias.exists?(username) and self[username].registered?
    end

    def find_by_alias(nick)
      cache.each {|username, user| return user if user.alias? nick }
      Alias.where(:alias => nick).first.try(:user)
    end
  end

  scope :registered, where('access_level != 0')

  # Helper methods
  def reload_attribute(attr)
    self[attr] = self.class.where(:id => id).select(attr).first[attr]
  end

  def [](key)
    if attribute = user_attr(key)
      value = attribute.value
      value = case attribute.class_name
        when 'String'   then value
        when 'Symbol'   then value.to_sym
        when 'Integer'  then value.to_i
        when 'Float'    then value.to_f
        else raise NotImplementedError, "reader for #{attribute.class_name} missing"
      end
    else
      super
    end
  end

  def []=(key, value)
    return super if attributes.keys.include? key.to_s
    attr = user_attr(key)
    return attr.delete if attr unless value
    attr ||= user_attributes.build(:key => key.to_s)
    attr.value = value
    attr.class_name = value.class.name
    attr.save
  end

  def user_attr(key)
    user_attributes.find_by_key(key.to_s)
  end

  # Virtual attributes
  def registered?
    persisted? and access_level != 0
  end

  def identified?(server_name)
    @identified_on.include? server_name
  end

  def aliases?
    !aliases.empty?
  end

  def alias?(nickname)
    aliases.collect {|a| a.alias.downcase }.include? nickname.downcase
  end

  #TODO: dynamic boolean methods for command types, eg. moderator?

  def access_level
    session_access_level || attributes['access_level']
  end

  def registered_servers
    registered_server.split(';').collect(&:to_sym)
  end

  def add_registered_server(server_name)
    return if registered_servers.include? server_name.to_sym
    servers = registered_servers << server_name.to_sym
    update_attribute :registered_server, registered_server = servers.join(';')
  end

  def remove_registered_server(server_name)
    return unless registered_servers.include? server_name.to_sym
    servers = registered_servers.tap {|s| s.delete server_name.to_sym }
    update_attribute :registered_server, registered_server = servers.join(';')
  end

  def password
    @plain_text_password
  end

  def password=(value)
    hashed_password = Digest::MD5.new.update(value).hexdigest
    @plain_text_password = value
    return if hashed_password == password_hash
    update_attribute :password_hash, hashed_password
  end

  def gender
    User.get_gender(gender_id || 0)
  end

  def gender=(value)
    value = User::Gender[value] if value.is_a? Symbol
    update_attribute :gender_id, value
  end

  def gender_noun
    GenderNoun[gender ? gender : 0]
  end

  def gender_pronoun
    GenderPronoun[gender ? gender : 0]
  end

  private
  def init
    @identified_on = []
    @plain_text_password = ""
  end
end

class UserAttribute < ActiveRecord::Base
  belongs_to :user

  class << self
    def [](key)
      attribute = where(key: key.to_s).first
      value = attribute.value
      value = case attribute.class_name
        when 'String'   then value
        when 'Symbol'   then value.to_sym
        when 'Integer'  then value.to_i
        when 'Float'    then value.to_f
        else raise NotImplementedError, "reader for #{attribute.class_name} missing"
      end
    end

    def []=(key, value)
      attribute = where(key: key.to_s).first || new(key, value)
      attribute.class_name = value.class.name
      attribute.value = value.to_s
      attribute.save
    end
  end
end

class Alias < ActiveRecord::Base
  self.table_name = 'aliases'
  belongs_to :user

  def self.exists?(nickname)
    count(:conditions => {:alias => nickname}) > 0
  end
end