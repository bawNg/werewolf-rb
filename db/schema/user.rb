ActiveRecord::Schema.define do
  create_table :users do |table|
    table.column :id,                 :integer
    table.column :username,           :string
    table.column :password_hash,      :string
    table.column :access_level,       :integer
    table.column :gender_id,          :integer
    table.column :registered_server,  :string, :default => ''
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
end