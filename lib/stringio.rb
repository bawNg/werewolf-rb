require 'stringio'

class StringIO
  def self.allocate(size)
    new "\0" * size
  end

  def byte
    read(1)[0].ord
  end

  def float
    read(4).unpack('e')[0]
  end

  def get
    read remaining
  end

  def long
    read(4).unpack('V')[0]
  end

  def remaining
    size - pos
  end

  def short
    read(2).unpack('v')[0]
  end

  def signed_long
    read(4).unpack('l')[0]
  end

  def cstring
    gets("\0")[0..-2]
  end
end