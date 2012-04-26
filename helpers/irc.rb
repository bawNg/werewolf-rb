module IrcHelpers #TODO: refactor to irc module
  [:privmsg, :notice].each do |method_name|
    define_method(method_name) do |*args|
      server_name = args.shift if args.first.is_a?(Symbol) and Irc.servers.include? args.first
      target = args.shift if args.length > 1 unless args.first.is_a? Symbol
      args = template_sub(args)
      message = args.reject(&:blank?).join(' ').to_irc
      lines = message.scan(/\S.{1,430}(?!\S)/)
      if server_name or respond_to? :send_cmd
        server = server_name ? Irc.servers[server_name] : self
        lines.each {|line| server.send_cmd(method_name, target || server.channel, line) }
      else
        Irc.servers.each do |name, server|
          lines.each {|line| server.send_cmd(method_name, target || server.channel, message) }
        end
      end
    end
  end

  def send_to_channel(*args)
    server_name = args.shift if args.first.is_a?(Symbol) and Irc.servers.include? args.first
    target = args.shift if args.length > 1 and args.first.is_a?(String) and args.first.starts_with? '#'
    return privmsg(*args) unless server_name
    privmsg server_name, target || Irc.servers[server_name].channel, *args
  end

  def set_topic(*args)
    target = server.channels.include?(args.first) ? args.shift : channel
    if args.first.is_a?(Symbol) and not [:topic, :base].include? args.first
      #puts "[set_topic] before: #{args.inspect}"
      options = args.pop if args.last.is_a? Hash
      args.collect! {|arg| [:seperator, arg] }.flatten!
      args.unshift :base
      args.unshift :topic
      args << options
      #puts "[set_topic] after: #{args.inspect}"
    end
    #puts "[set_topic] topic identifier: #{topic_identifier}"
    return if server.channels[channel][:topic] == args
    server.channels[channel][:topic] = args
    args = template_sub(args)
    #puts "[set_topic] after substitution: #{args.inspect}"
    send_cmd :topic, target, args.join.to_irc
  end

  def send_reply(*msgs)
    type = msgs.shift if msgs.length > 1 and [:privmsg, :notice].include? msgs.first
    if @event.target[0, 1] == '#'
      reply_cmd = type || @event.server.config.channel_reply_command || :privmsg
      log :yellow, "[send_reply] sending #{reply_cmd} to #{reply_cmd == :notice ? @event.nickname : @event.channel}: #{msgs.inspect}"
      send(reply_cmd, reply_cmd == :notice ? @event.nickname : @event.channel, *msgs)
    else
      send(type || @event.msg_type || :privmsg, @event.nickname, *msgs)
    end
  end

  def send_error(*msgs)
    msgs = [@invalid_syntax] if @invalid_syntax and msgs.first == :invalid_syntax
    send_reply(*msgs)
    raise CommandError
  end

  def template_sub(msgs)
    if msgs[0..1].all? {|msg| msg.is_a? Symbol }
      category_name = msgs.shift.to_s
      if category = $template[category_name]
        substitutions = msgs.pop if msgs.last.is_a? Hash
        messages, message = [], ''
        msgs.each do |key|
          #puts "[template_sub] msgs.each do |#{key}|"
          if msg = category[key.to_s]
            #puts "[template_sub] msg in #{category_name}[#{key.inspect}]: #{msg}"
            if msg.is_a? String
              message << msg
            elsif msg.is_a? Array
              unless message.blank?
                messages << message
                message = ''
              end
              messages += msg
            end
          end
          #puts "[template_sub] #{key}: #{msg}"
        end
        messages << message unless message.blank?
        #puts "[template_sub] before: #{messages}"
        if substitutions
          #puts "[template_sub] substitutions: #{substitutions.inspect}"
          substitutions.each do |key, value|
            messages.each {|msg| msg.gsub! "$#{key}", value.to_s }
          end
        end
        #puts "[template_sub] after: #{messages}"
        msgs = messages unless messages.empty?
      end
    end
    msgs
  end
  module_function :template_sub

  def game=(value)
    server.channels[server.channel][:game] = @event.game = value
  end
end