def pluralize(count, singular, plural = nil)
  "#{count || 0} " + ((count == 1 || count =~ /^1(\.0+)?$/) ? singular : (plural || singular.pluralize))
end

def spam_percentage(lines)
  stop_words = %w[ a about above after again against all am an and any are aren't as at be because been before being
                   below between both but by can't cannot could couldn't did didn't do does doesn't doing don't down
                   during each few for from further had hadn't has hasn't have haven't having he he'd he'll he's her
                   here here's hers herself him himself his how how's i i'd i'll i'm i've if in into is isn't it it's
                   its itself let's me more most mustn't my myself no nor not of off on once only or other ought our
                   ours ourselves out over own same shan't she she'd she'll she's should shouldn't so some such than
                   that that's the their theirs them themselves then there there's these they they'd they'll they're
                   they've this those through to too under until up very was wasn't we we'd we'll we're we've were
                   weren't what what's when when's where where's which while who who's whom why why's with won't
                   would wouldn't you you'd you'll you're you've your yours yourself yourselves ]
  words = lines.collect do |line|
    urls = URI.extract(text = line.dup)
    urls.each {|url| text.gsub! url, '' }
    (text.scan(/\w+/) + urls).collect(&:downcase)
  end
  words.flatten!

  words -= stop_words
  uniq_words_size = words.uniq.size
  ((words.size - uniq_words_size) + 1) / words.size.to_f * 100
end

def log(*msgs)
  colour = msgs.first.is_a?(Symbol) ? msgs.shift : :default
  puts msgs.join(' ').colorize(colour)
end

def log_to_file(filename, *args)
  File.open("log/#{$prefix}#{filename}.log", 'a') do |file|
    file.puts "[#{Time.now.strftime "%a %d %B %Y %I:%M:%S %p"}] #{args.join ' '}"
  end
end

def log_exception(ex, action=nil)
  message = "Exception#{" while #{action}" if action}: #{ex.message.gsub(/\n/, ' ')}\n#{ex.backtrace.join "\n"}"
  log_to_file(:exceptions, message, "\n")
  log :red, "Exception raised#{" while #{action}" if action}: #{ex.message.gsub(/\n/, ' ')}"
  ex.backtrace.each {|line| print "#{line}\n".light_red }
end