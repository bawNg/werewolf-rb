class Array
  def group_by_start(min=1, max=-1)
    found = {}

    self.each do |string|
      comparison_string = block_given? ? yield(string) : string
      comparison_string = comparison_string[0..max]
      (min - 1).upto(comparison_string.size) do |i|
        found[comparison_string[0, i+1]] ||= []
        break if comparison_string[i..i+1] =~ /\W/
      end
    end

    found.each do |key, matches|
      self.each do |string|
        comparison_string = block_given? ? yield(string) : string
        matches << string if comparison_string[0..max].start_with? key
      end
    end

    found.reject! {|_, value| value.empty? }
    found.reject {|start, values| found.except(start).any? {|s, v| start.start_with?(s) && (values.size <= v.size) } }
  end
end