module Model
  class << self
    def load(name)
      model_path = "#{File.expand_path(File.dirname(__FILE__))}/model/#{name.underscore}.rb"
      return false unless File.exists? model_path
      unload(name)
      Kernel.load(model_path)
      class_name = name.classify
      log :green, "[Model] Loaded model: #{class_name}"
      unless class_name.constantize.table_exists?
        log :green, "[Model] Creating schema for table: #{class_name}"
        schema_path = "#{File.expand_path(File.dirname(__FILE__))}/db/schema/#{name.underscore}.rb"
        Kernel.load(schema_path)
      end
      true
    end

    def load_all
      Dir.glob(File.expand_path(File.dirname(__FILE__)) + '/model/*.rb') do |file_path|
        load(File.basename(file_path, '.rb'))
      end
      log :green, "[Model] Loaded all models."
    end

    def unload(name)
      #puts "[Model#unload] Removing constant: #{name.classify}" if Object.const_defined? name.classify
      Object.send :remove_const, name.classify if Object.const_defined? name.classify
    end

    def reload(name)
      unload(name)
      load(name)
    end
  end
end