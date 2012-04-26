require '../on_irc/lib/on_irc'
%w(connection server config).each {|file| require "../on_irc/lib/on_irc/#{file}" }

module Irc #TODO: rescue from exceptions that occur inside irc library callbacks
  Config = Struct.new(:address, :port, :channel, :channel_id, :nick, :ident, :realname, :ssl, :channel_reply_command)

  class << self
    attr_accessor :irc, :last_join_event
    delegate :servers, :to => :irc
  end

  @irc = IRC.new(nick: config.nickname.first, ident: Core::Name, realname: "#{Core::Name} v#{Core::Version}")

  on :loaded do
    config.servers.each do |server|
      if $dev_channel
        server.channel['id'] = -1 unless $dev_channel.downcase == server.channel.name.downcase
        server.channel['name'] = $dev_channel
      end
      cfg = Config.new(server.address, server.port, server.channel.name, server.channel['id'])
      cfg.ssl = server['ssl']
      cfg.channel_reply_command = :notice
      irc.config.servers[server.name.to_sym] = cfg
      servers[server.name.to_sym] = IRC::Server.new(irc, server.name.to_sym, cfg)
    end

    next log :red, "Warning: There are no IRC servers enabled!" if config.servers.size == 0

    log :green, "Connecting to IRC #{'server'.pluralize(servers.size)}..."
    servers.values.each do |server|
      begin
        server.connection = EM.connect(server.address, server.port, IRC::Connection, server)
      rescue EM::ConnectionError => ex
        log :red, "[#{server.address}:#{server.port}] #{ex.message} (#{ex.class.name})"
        retry
      end
    end
  end

  on :unloaded do
    servers.values.each do |server|
      server.disconnect 'Module unloaded'
    end
  end

  irc.on :pre_respond do
    msgs = IrcHelpers.template_sub(params)
    msgs.collect!(&:to_irc)
    [command, msgs]
  end

  irc.on :all do #NOTE: irc.on events are fired by the irc library and have no exception handling
    log :magenta, "#{server.name}: #{"#{sender} " unless sender.blank?}#{command.to_s.upcase} #{target} #{params.inspect}"
    next if sender.server? && !sender.username
    ignored_nicks = [server.name.to_s, 'ChanServ', 'NickServ', 'AresServ', 'IRC'].collect(&:downcase)
    next if ignored_nicks.include? sender.nick.downcase

    unless command == :join # fire join event after identified status has been updated
      EM.add_timer(0.25) { Modules.on(command, self.dup) }
    end

    next if sender.nick.downcase == server.current_nick.downcase || server.config.channel_id < 0

    unless params.blank?
      next if params.first.strip.blank? || params.first.length < 2
      cmd = (params.first[0, 1] == '!' ? params.first[1..-1] : params.first).split(' ').first
      next if %w[ seen identify setpass send say quit ].include?(cmd.downcase) unless cmd.blank?
    end
    #Log.create(:user_id => User[sender.username].id, :channel_id => channel ? server.config.channel_id : -1,
    #           :command => command.to_s.upcase, :nickname => sender.nick, :target => target, :message => params.join(' '))
  end

  irc.on :join do
    Irc.last_join_event = self.dup if server.current_nick.downcase == sender.nick.downcase
    next if ['chanserv', server.current_nick.downcase].include? sender.nick.downcase

    server.user[sender.nick].username ||= sender.nick

    if server.user[sender.nick].identified? server.name
      puts "already identified"
      next Modules.on(:join, self)
    end

    puts "checking identity..."
    server.on_identified_update sender.nick do
      puts "on_identified_update"
      next Modules.on(:join, self) unless User.exists? sender.nick

      # User is registered in the database
      irc_user = server.user[sender.nick]
      user = irc_user.identified_as ? User[irc_user.identified_as] : User[sender.nick]
      irc_user.username = user.username
      Modules.on(:join, self)
    end

    send_cmd :who, sender.nick unless server.ircd =~ /ircd-seven/ #TODO: move to irc lib
  end

  irc.on :pre_reconnect do
  end

  irc.on :connected do
    mode server.current_nick, "+B" unless server.ircd =~ /ircd-seven/
    server_config = $config.irc.servers.detect {|s| s.name == server.name.to_s }
    privmsg :NickServ, "identify #{server_config.password}" if server_config
    send_cmd :join, server_config.channel.name
  end

  irc.on :identified_update do
    next if [server.current_nick, 'ChanServ'].include? target
    if sender.user && sender.user.identified?
      if server.ircd =~ /ircd-seven/ && !sender.user.identified_as
        next User[sender.user.username].identified_on.delete(server.name)
      end
      user = User[sender.nick]                                                 #TODO: refactor to irc lib, always using identified_as, regardless of the IRCd
      if identified_as = sender.user.identified_as
        # set irc users username to the username they are identified to NickServ with unless sender.nick is registered
        user = User[identified_as] if User[identified_as].registered? unless User[sender.nick].registered?
      end
      sender.user.username = user.username
      user.nickname = sender.nick
      next user.update_attribute :updated_at, Time.now unless user.registered? #TODO: make a config attribute for temporary unregistered user storage
      next unless user.registered_servers.include? server.name
      next if identified_as && user.id != User[identified_as].id
      log :cyan, "[on_identified_update] Auto logged in user: #{user.username.inspect} on #{server.name}. #{user.inspect}"
      user.identified_on << server.name unless user.identified? server.name
      user.update_attribute :updated_at, Time.now
      if modes = server.channels[server.config.channel][:user_modes][sender.nick]
        access_level = case modes.uniq.join ''
          when /q/   then Command::Type::SuperAdmin
          when /a|o/ then Command::Type::Admin          #TODO: implement for manual logins
          when /h|v/ then Command::Type::Moderator
        end
        user.session_access_level = access_level if access_level && user.access_level < access_level
      end
    end
  end

  on :'315' do # end of who
    if Irc.last_join_event
      Modules.on :join, Irc.last_join_event
      Irc.last_join_event = nil
    end
  end

  on :'353' do # names
    params[2].split(" ").each do |nick|
      nick.slice!(0) if %w[ ~ & @ % + ].include? nick[0, 1]
      server.user[nick].username ||= nick
    end
  end

  on :'433' do # nickname in use
    send_cmd :nick, $config.irc.nickname.last
  end

  on :mode do
    if channel
      modes = params.shift
      params.each do |param|
        next unless irc_user = server.user[param]
        next unless (user = User[irc_user.username]).registered?
        log :yellow, "[on_mode] checking if #{param} is registered on #{server.name}"
        next unless user.registered_servers.include? server.name
        log :yellow, "[on_mode] checking if #{param} is identified on #{server.name}"
        next unless user.identified? server.name
        if modes = server.channels[server.config.channel][:user_modes][irc_user.nickname]
          access_level = case modes.uniq.join ''
            when /q/   then Command::Type::SuperAdmin
            when /a|o/ then Command::Type::Admin          #TODO: implement for manual logins
            when /h|v/ then Command::Type::Moderator
          end
          user.session_access_level = access_level if access_level && user.access_level < access_level
        else
          log :yellow, "[on_mode] No modes for #{param}"
          user.session_access_level = nil if user.session_access_level.present?
        end
      end
    end
  end

  on :join do
    send_reply :notice, :channel, :join, channel: channel if target.downcase == server.channel.downcase

    irc_user = server.user[sender.nick]
    next unless irc_user.identified?

    # Nick is identified to nickserv
    unless User.exists? sender.nick
      # Nick is not registered
      send_error :notice, "You may register an account with the !register command so that your stats can be saved."
    end

    if user.registered? and !user.registered_servers.include? server.name
      # User registered on a different server
      send_reply :notice, "This account has been registered on a different server."
      send_error :notice, "You need to manually identify in order to use it here. (!help pass)"
    end
    send_reply :notice, "You have been automatically logged into your account."
    if user.password_hash.blank?
      send_reply :notice, "Your account has no password set! Use \"/msg #{server.current_nick} setpass <pass>\"."
    end
    send_reply :notice, 'Your account has no gender set! Use "!setgender <male|female>".' if user.gender == :none
  end

  on :part do
    next if ['ChanServ', server.current_nick].include? sender.nick
    next unless user = User[sender.user.username]
    next unless target.downcase == server.channel.downcase
    user.identified_on.delete(server.name)
    user.session_access_level = nil
  end

  on :quit do
    if sender.nick == $config.irc.nickname.first
      send_cmd :nick, $config.irc.nickname.first
      server.current_nick = $config.irc.nickname.first
    end
    next if !sender.user or ['ChanServ', server.current_nick].include? sender.nick
    next unless user = User[sender.user.username]
    user.identified_on.delete(server.name)
    user.session_access_level = nil
  end

  on :nick do
    next if [sender.nick, target].include? server.current_nick

    server.on_identified_update new_nick do
      unless irc_user = server.user[new_nick = target]
        next log :cyan, "Ignoring nick change to #{new_nick.inspect}. (user no longer exists)"
      end

      if new_nick.downcase == irc_user.username.downcase
        send_cmd :notice, new_nick, "Nick tracking: You are using your real nick. If this is wrong please use the !mynickis command."
        next # new nick is old nicks username
      end

      if irc_user.identified? and User.exists? new_nick
        irc_user.username = User[new_nick].username
        User[new_nick].nickname = new_nick
        type = Alias.exists?(new_nick) ? :aliased : :registered
        send_cmd :notice, new_nick, "Nick tracking: You are now using your #{type} nickname, if this is wrong please use the !mynickis command."
      elsif irc_user.identified? and identified_as = sender.user.identified_as and User[identified_as].registered?
        # set irc users username to the username they are identified to NickServ with unless new_nick is registered
        irc_user.username = User[identified_as].username if User[identified_as].registered? unless User[new_nick].registered?
        send_cmd :notice, new_nick, "Nick tracking: You are now known as #{identified_as}, if this is wrong please use the !thisismynick command."
      elsif !User.exists? new_nick and User.exists? irc_user.username
        send_cmd :notice, new_nick, "Nick tracking: You are still known as #{irc_user.username}, if this is wrong please use the !thisismynick command."
      else
        # new nick and old nicks username are both unregistered
        irc_user.username = new_nick
        User[sender.nick].nickname = sender.nick
        send_cmd :notice, new_nick, "Nick tracking: You are not identified to NickServ." unless irc_user.identified?
      end
    end
  end

  on :privmsg do
    next unless params.length > 0

    # Spam filtering
    #TODO: general bot flood protection
    #166 spamfilter users that send 5 or more lines within a second of each other more than once every 15 minutes
    #167 spamfilter users that send 3 or more lines within a second of each other within 15 seconds of joining the channel
    # set mode +R after X joins
    if target[0, 1] == '#'
      # User is speaking in a channel
      recent_msgs = [] #Log.privmsg.nickname(sender.nick).created_at(6.seconds.ago .. Time.now).collect(&:message)

      log :yellow, "#{sender.nick}'s spam percentage over the last #{recent_msgs.size}: #{spam_percentage(recent_msgs)}" if recent_msgs.size > 2

      last_join = 1.hour.ago #Log.join.nickname(sender.nick).last
      if recent_msgs.size > 5 && last_join && last_join.created_at > 30.seconds.ago
        # User has sent 3 of more messages in the past 6 seconds and user joined the channel less than 30 seconds ago

        user = User[server.user[sender.nick].username]
        if user.registered? and user.identified? server.name #TODO: wait until checked identified status
          case recent_msgs.size
            when 3
              if %w[ ivan markov ].include? sender.nick.downcase
                send_cmd :mode, channel, '+b', "~q:#{sender.nick}"
              else
                notice sender.nick, "You are not a spambot, but continue to behave like one and you will be treated as such."
              end
            when 4 then notice sender.nick, "I will not warn you again..."
            when 5
              unless %w[ ivan markov ].include? sender.nick.downcase
                send_cmd :kick, channel, sender.nick, "Faulty human detected. Have you tried turning it off and on again?"
              end
          end
        else
          unless recent_msgs.size < 7 and spam_percentage(recent_msgs) < 100 - (recent_msgs.size * 10) #FIXME: logic error
            hostmasks = %W[ #{sender.nick}!*@* ]
            hostmasks << "*!*@#{sender.user.hostname}" if sender.user.hostname
            Ban.create nicknames: sender.nick, hostmasks: hostmasks.join(' '), reason: 'Spammed channel 3 times within 15 seconds of joining'

            send_cmd :mode, target, "+bb", *hostmasks
            send_cmd :kick, target, sender.nick, "Spambot"
          end
        end
      end

      #msgs_since_join = Log.where(:nickname => sender.nick, :command => 'PRIVMSG',
      #                            :target => target, :created_at => last_join.created_at .. Time.now)
      #groups = msgs_since_join.inject([]) do |groups, msg|
      #  if not groups.empty? and (groups.last.first.created_at .. groups.last.first.created_at + 1.second).include? msg.created_at
      #    groups.last << msg
      #  else
      #    groups << [msg]
      #  end
      #end
      #if groups.any? {|msgs| msgs.count >= 3 }
        # User has sent at least 3 lines within a second of each other within 15 seconds of joining the channel
        #Ban.create(:user_id => -1, :nicknames => sender.nick, :hostmasks => "#{sender.nick}!*@* *!*@#{sender.host}",
        #           :reason => "User flooded channel shortly after joining")
        #TODO: complete...
      #end
    end

    unless sender
      next send_reply "An error occurred while processing your request. :(" #TODO: query user info from services if user is not in a channel the bot is in
    end

    next unless params.first.length > 1

    if params.first.length > 1 and params.first[0, 1] == $config.irc.command_trigger || target.downcase == server.current_nick.downcase
      next if params.first[1, 2] == '!' unless target[0, 1] == '#'
      next Command.new(server, :privmsg, sender, target, params.first) if params.first.split(' ').first.length > 1
    end

    unless params.first.start_with? '?'
      # URL title fetching
      if params.first =~ /((http|https):\/\/)?[\w\-_]+(\.[\w\-_]+)+([\w\-\.,@?^=%&amp;:\/~\+#]*[\w\-@?^=%&amp;\/~\+#])?/
        unless [:jpg, :jpeg, :gif, :png].any? {|ext| $~[0].ends_with? ext.to_s }
          UrlTitle.get($~.to_s.gsub(/^(http:\/\/)?/, 'http://')) do |title| #TODO: debug UrlTitle and remove http:// workaround
            next if title.include? '404 Not Found'
            msg channel, "Title: #{title} (#{$~.to_s[/^(http:\/\/)?([^\/]+)/, 2]})"
          end rescue nil #TODO: catch any unusual issues such as encoding errors until UrlTitle has better error handling
        end
      end
      next
    end
  end

  on :notice do
    if sender.nick == "NickServ" and params.first =~ /^This nickname is registered( and protected)?\..*IDENTIFY.*password/i
      # identify on connect for speedy debugging
      server_config = $config.irc.servers.detect {|s| s.name.to_sym == server.name }
      privmsg :NickServ, "identify #{server_config.password}" if server_config
    elsif sender.nick == "NickServ" and params.first =~ /You are now (recognized|identified)/i
      join server.channel
    else
      next if sender.server? || params.length < 1
      next if [server.current_nick.downcase, 'chanserv', 'nickserv', 'aresserv', 'services'].include? sender.nick.downcase
      Command.new(server, :notice, sender, target, params.first)
    end
  end

  on :kick do
    send_cmd :join, target if params.first == server.current_nick
  end
end