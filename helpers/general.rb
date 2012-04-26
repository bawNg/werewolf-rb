module GeneralHelpers
  def ordinalize(number)
    if number.to_i == 1
      'first'
    elsif (11..13).include?(number.to_i % 100)
      "#{number}th"
    else
      case number.to_i % 10
        when 1; "#{number}st"
        when 2; "#{number}nd"
        when 3; "#{number}rd"
        else    "#{number}th"
      end
    end
  end

  def hostmask_to_regex(hostmask)
    regex = hostmask.gsub('*', '.+').gsub('?', '[A-Za-z0-9\-]').split(/[!@]/).collect do |part|
      part.include?('[A-Za-z0-9\-]') or part.include?('.+') ? part : '(' + part + '|\*)'
    end
    regex[1] ||= '[^@]+'
    regex[2] ||= '.+'
    /^#{"%s!%s@%s" % regex}$/i
  end

  def time(string, options={})
    Chronic.parse(string, options)
  end

  def timespan(string, options={})
    Chronic.parse(string, options.merge(guess: false))
  end
  
  def distance_of_time_in_words(from_time, to_time = Time.now, include_seconds = true, options = {})
    from_time = from_time.to_time if from_time.respond_to?(:to_time)
    to_time = to_time.to_time if to_time.respond_to?(:to_time)
    distance_in_minutes = (((to_time - from_time).to_f.abs) / 60).round
    distance_in_seconds = ((to_time - from_time).to_f.abs).round


    case distance_in_minutes
      when 0..1
        return distance_in_minutes == 0 ? "less than 1 minute" : "#{distance_in_minutes} minutes" unless include_seconds

        case distance_in_seconds
          when 0..4   then "less than 5 seconds"
          when 5..9   then "less than 10 seconds"
          when 10..19 then "less than 20 seconds"
          when 20..39 then "half a minute"
          when 40..59 then "less than 1 minute"
          else             "1 minute"
        end

      when 2..44           then "#{distance_in_minutes} minutes"
      when 45..89          then "about 1 hour"
      when 90..1439        then "about #{(distance_in_minutes.to_f / 60.0).round} hours"
      when 1440..2529      then "1 day"
      when 2530..43199     then "#{(distance_in_minutes.to_f / 1440.0).round} days"
      when 43200..86399    then "about 1 month"
      when 86400..525599   then "#{(distance_in_minutes.to_f / 43200.0).round} months"
      else
        distance_in_years           = distance_in_minutes / 525600
        minute_offset_for_leap_year = (distance_in_years / 4) * 1440
        remainder                   = ((distance_in_minutes - minute_offset_for_leap_year) % 525600)
        if remainder < 131400
          "about #{distance_in_years} years"
        elsif remainder < 394200
          "over #{distance_in_years} years"
        else
          "almost #{distance_in_years + 1} years"
        end
    end
  end

  def requires(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    @required_parameters = args.collect(&:to_s)
    @optional_parameters = Array.wrap(options[:optional]).collect(&:to_s)
    usage = "#{$config.irc.command_trigger}#{command} <#{@required_parameters.collect(&:deunderscore).join '> <'}>"
    usage << " [#{@optional_parameters.collect(&:deunderscore).join '], ['}]" if @optional_parameters.present?
    @invalid_syntax = "Invalid syntax! Usage: #{usage}"
    @required_parameters.each_with_index do |arg, index|
      send_error "You need to specify a #{arg}. Usage: #{usage}" unless all_params[index]
    end
  end

  def optional(*args)
    @optional_parameters = args.collect(&:to_s)
  end

  def send_invalid_syntax_error
    send_error @invalid_syntax
  end

  def send_error(*msgs)
    #send_reply(*msgs)
    raise ArgError, msgs
  end

  def benchmark(*msgs, &block)
    options = msgs.last.is_a?(Hash) ? msgs.pop : {}
    t = Time.now
    result = yield
    message = msgs.join ' '
    message.gsub!(/\{\{(.+?)\}\}/) do
      $1.starts_with?('ret.') ? eval($1.gsub('ret.', 'result.')) : block.binding.eval("(#$1) rescue 'nil'")
    end
    message = "Took %f seconds to #{message}" % (Time.now - t)
    if !options.include?(:if) || options[:if]
      #if EM.reactor_thread?
        options[:log_to] ? log_to_file(options[:log_to], message) : puts(message)
      #else
      #  next_tick { ... }
      #end
    end
    result
  end

  def call_with_rescue(block, *args)
    begin
      catch(:done) { block.call(*args) }
    rescue Exception => ex
      log :red, "Exception raised while involking callback: #{ex.message.gsub(/\n/, ' ')}"
      ex.backtrace.each {|line| print "#{line}\n".light_red }
    end
  end

  def print_backtrace
    raise RuntimeError
  rescue RuntimeError => ex
    ex.backtrace.each {|line| print "#{line}\n" }
  end
end