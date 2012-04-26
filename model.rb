module Model
  @base_classes = {}

  class << self
    def load(name)
      file_name = File.expand_path(File.dirname(__FILE__)) + "/model/#{name.underscore}.rb"
      return false unless File.exists? file_name
      unload(name)
      Kernel.load file_name
      puts "[Model] Loaded model: #{name.classify}"
      true
    end

    def load_all
      Dir.glob(File.expand_path(File.dirname(__FILE__)) + '/model/*.rb') do |file_name|
        Kernel.load file_name
      end
      puts "[Model] Loaded all models."
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