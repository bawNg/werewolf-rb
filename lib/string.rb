class String
  def numeric?
    true if Float(self) rescue false
  end

  def starts_with(str)
    self[0, str.length] == str
  end

  def ends_with(str)
    self[self.length - str.length, str.length] == str
  end

  def to_underscore
    self.gsub(/([a-z]+)([A-Z][a-z]+)/, '\1_\2').downcase
  end

  def to_irc
    pairs = { '#B' => "\002", "#U" => "\037", "#R" => "\026", "#C" => "\003", "#O" => "\017" }
    gsub /#([#{pairs.keys.collect {|key| key[-1, 1]}.join}])/ do
      pairs["##{$1}"].to_str
    end
  end

  def deunderscore
    gsub /_/, ' '
  end

  def shorten_urls
    gsub /((http|https):\/\/)[\w\-_]+(\.[\w\-_]+)+([\w\-\.,@?^=%&amp;:\/~\+#]*[\w\-@?^=%&amp;\/~\+#])?/ do
      Bitly.shorten($~[0]).jmp_url
    end
  end

  def to_relative_path
    Pathname.new(self).relative_path_from(Pathname.new(Dir.pwd)).to_s
  end
end