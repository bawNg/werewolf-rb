class Hash
  def method_missing(method, *args)
    method_name = method.to_s
    unless respond_to? method_name
      if method_name.ends_with? '?'
        method_name.slice! -1
        key = keys.detect {|k| k.to_s == method_name }
        return !!self[key]
      elsif method_name.ends_with? '='
        method_name.slice! -1
        key = keys.detect {|k| k.to_s == method_name }
        return self[key] = args.first
      end
    end
    key = keys.detect {|k| k.to_s == method_name }
    return self[key] if key
    super
  end
end

if defined? IRC::DowncasedHash
  class SymbolHash < IRC::DowncasedHash
    def [](key)
      super string_get_key(key)
    end

    def []=(key, value)
      super string_get_key(key, value)
    end

    def delete(key)
      super string_get_key(key)
    end

    def include?(key)
      super string_get_key(key)
    end

   private
    def string_get_key(key)
      key = key.to_s
      keys.detect {|k| k.to_s == key }
    end
  end
end