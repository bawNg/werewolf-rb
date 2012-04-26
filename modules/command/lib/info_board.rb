require './lib/string'

#TODO: round off board lengths to the nearest 2, (n & 1)

class InfoBoard
  attr_reader :lines, :send_method

  def self.send_method=(method)
    @@send_method = method
  end

  def initialize(header_or_reply_method="")
    case header_or_reply_method
      when String then header_text  = header_or_reply_method
      when Method then @send_method = header_or_reply_method
    end
    @lines = [@header = Header.new(header_text || '')]
  end

  def header
    @header.output
  end

  def header=(value)
    @header.text = value
  end

  def prepend_to_header(value)
    @header.text = value + @header.text
  end

  def add_header(text)
    @lines << Header.new(text.to_s.to_irc)
    update_line_lengths
  end

  def add_sub_header(text)
    @lines << SubHeader.new(text.to_s.to_irc)
    update_line_lengths
  end

  def add_line(text)
    @lines << Line.new(text.to_s.to_irc)
    update_line_lengths
  end

  def add_list_item(key, value="")
    key, value = key.to_s, value.to_s
    value, key = key, value if value.empty?
    @lines << ListItem.new(self, @lines.select {|line| line.is_a? ListItem }.count+1, key, value)
    update_line_lengths
  end

  def add_split_line(key, value)
    @lines << SplitLine.new(key.to_s, value.to_s)
    update_line_lengths
  end

  def send_lines(method=nil)
    @lines.each do |line|
      if method
        method(line.output)
      elsif @send_method
        @send_method.call(line.output)
      end
    end
  end

  def update_line_lengths
    max_length = highest_line_length
    @lines.each do |line|
      line.length = max_length
    end
  end

  def highest_line_length
    @lines.collect {|line| line.length }.max
  end

  class Header
    attr_accessor :length
    attr_reader :text

    def initialize(value="")
      @length = value.length
      self.text = value
    end

    def text=(value)
      @text = value
      @length = InfoBoard.visible_char_count(output)
    end

    def output
      n = @length - @text.length + 2
      n = 0 if n < 0
      #If n And 1 Then extraspace = Chr(32)
      "#C1,1#{' '*(n/2)}#C9,1#{@text}#C1,1#{' '*(n/2)}#{n.odd? ? ' ' : ''}".to_irc
    end
  end

  class SubHeader < Header
    def output
      n = @length - @text.length
      "#C5,5#{' '*(n/2)}#C15,5#{@text}#C5,5#{' '*(n/2)}#{n ? ' ' : ''}".to_irc
    end
  end

  class Line
    attr_accessor :length
    attr_reader :text

    def initialize(value="")
      @length = InfoBoard.visible_char_count(value)
      self.text = value
    end

    def text=(value)
      @text = value
      @length = InfoBoard.visible_char_count(output)
    end

    def output
      @length ||= @text.length + InfoBoard.invisible_char_count(@text)
      n = @length - @text.length + InfoBoard.invisible_char_count(@text) + 1
      "#C1,8 #{@text}#C8,8#{' '*n}".to_irc
    end
  end

  class ListItem
    attr_accessor :index, :key, :length
    attr_reader :value
    
    def initialize(info_board, index=1, key="", value="")
      @info_board = info_board
      @index = index
      @key = key
      @length = InfoBoard.visible_char_count(index, key, value)
      self.value  = value
    end

    def value=(value)
      @value = value
      @length = InfoBoard.visible_char_count(output)
    end

    def output
      number = @index.to_s
      number << ' ' if @index < 10 # fix number spacing if number is only 1 digit
      text_length = [number, @key, @value].inject(0) {|sum, str| sum + str.length }
      #n = @length - (number.length + @key.length + @value.length - 1)
      #n += InfoBoard.invisible_char_count(key, value)
      #n -= 6
      n = @info_board.lines.select {|line| line.is_a? ListItem }.collect {|line| line.key.length }.max
      n = @key.length unless n
      n += 2
      n -= InfoBoard.visible_char_count(key)
      second = @length - InfoBoard.visible_char_count(number, @key, @value) - n
      second = 0 if second < 0
      n -= 1
      n = 0 if n < 0
      return "#R#{number}#R#C1,8 #@value#C8,8#{' '*n} #{' '*second} ".to_irc if @key.empty? 
      "#R#{number}#R#C1,8 #@key#C8,8#{' '*n}#C1,8-#C8,8#{' '*second}#C01,08#@value ".to_irc
    end
  end

  class SplitLine
    attr_accessor :key, :length
    attr_reader :value

    def initialize(key="", value="")
      @key = key
      @length = InfoBoard.visible_char_count(key, value)
      self.value = value
    end

    def value=(value)
      @value = value
      @length = InfoBoard.visible_char_count(output)
    end

    def output
      n = (@length - @key.to_s.length - @value.to_s.length - 2) + InfoBoard.invisible_char_count(key, value)
      n = 0 if n < 0
      spacing = ' ' * n
      end_spacing_n = (@length - @key.length - @value.length - n - 1)
      end_spacing_n = 0 if end_spacing_n < 0
      end_spacing = ' ' * end_spacing_n
      
      "#C1,8 #@key#C8,8#{spacing}#C1,8  #@value#C8,8#{end_spacing}".to_irc
    end
  end

  def self.visible_char_count(*strings)
    strings.inject(0) do |sum, str|
      s = str.to_s.dup
      s = str.to_s unless str.is_a? String
      s.gsub! /\003(?:\d{1,2}(?:,\d{1,2})?)?/, '' # remove colour bytes and codes
      s.gsub! /[\002\017\026\031\037]/, ''        # remove formatting bytes
      sum + s.length
    end
  end

  def self.invisible_char_count(*strings)
    strings.inject(0) {|sum, str| sum + str.length } - visible_char_count(*strings)
  end
end