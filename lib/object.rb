if RUBY_VERSION < "1.9"
  class Object
    def instance_exec(*args, &block)
      mname = "__instance_exec_#{Thread.current.object_id.abs}"
      class << self; self end.class_eval{ define_method(mname, &block) }
      begin
        ret = send(mname, *args)
      ensure
        class << self; self end.class_eval{ undef_method(mname) } rescue nil
      end
      ret
    end
  end
end

alias _puts_ puts
def puts(*args)
  args[0] = args.first.to_s unless args.first.is_a? String
  args = ["[#{Time.now.strftime('%H:%M:%S')}] #{args.shift}", *args]
  _puts_ *args
end

def module_exists?(module_name)
  klass = Module.const_get(module_name)
  klass.class == Module
rescue NameError
  false
end