# Schema definitions - Create database schema with: load './db/schema.rb'
ActiveRecord::Schema.define do
  create_table :dictionary do |table|
    table.column :id,             :integer
    table.column :user_id,        :integer
    table.column :keyword,        :string
    table.column :message,        :string
    table.column :locked,         :integer
    table.column :requested,      :integer, default: 0
    table.timestamps
  end

  create_table :rss_feeds do |table|
    table.column :id,             :integer
    table.column :user_id,        :integer
    table.column :url,            :string
    table.column :display_format, :string
    table.column :announce_in,    :string
    table.column :poll_interval,  :string
    table.column :last_error,     :string
    table.column :last_pub_date,  :datetime
    table.timestamps
  end

  create_table :users do |table|
    table.column :id,                 :integer
    table.column :username,           :string
    table.column :password_hash,      :string
    table.column :access_level,       :integer
    table.column :gender_id,          :integer
    table.column :games_played,       :integer
    table.column :games_admined,      :integer
    table.column :registered_server,  :string, :default => ''
    table.column :steam_id,           :string
    table.timestamps
  end
  add_index :users, :id

  create_table :aliases do |table|
    table.column :id,      :integer
    table.column :alias,   :string
    table.column :user_id, :integer
  end
  add_index :aliases, :user_id

  create_table :user_attributes do |table|
    table.column :user_id,    :integer
    table.column :class_name, :string
    table.column :key,        :string
    table.column :value,      :string
    table.timestamps
  end
  add_index :user_attributes, :user_id

  create_table :bans do |table|
    table.column :id,        :integer
    table.column :user_id,   :integer
    table.column :nicknames, :string
    table.column :hostmasks, :string
    table.column :reason,    :string
    table.timestamps
  end
  add_index :bans, :user_id

  create_table :news do |table|
    table.column :id,      :integer
    table.column :user_id, :integer
    table.column :message, :string
    table.timestamps
  end
  add_index :news, :id

  create_table :todos do |table|
    table.column :id,      :integer
    table.column :user_id, :integer
    table.column :text,    :string
    table.timestamps
  end
  add_index :todos, :id

  create_table :logs do |table|
    table.column :id,         :integer
    table.column :user_id,    :integer
    table.column :channel_id, :integer
    table.column :command,    :string
    table.column :nickname,   :string
    table.column :target,     :string
    table.column :message,    :string
    table.timestamps
  end
  add_index :logs, :id
end