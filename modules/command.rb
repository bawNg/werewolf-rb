class Command
  module Type
    Disabled    = -1
    Public      = 0
    Registered  = 1
    Moderator   = 5
    Admin       = 10
    SuperAdmin  = 20
    Owner       = 50
  end
  Level = { :identstatus            => Type::Public,
            :modules                => Type::Public,
            :toggle                 => Type::SuperAdmin,
            :say                    => Type::SuperAdmin,
            :send                   => Type::Owner,
            :module                 => Type::Owner,
            :restart                => Type::Owner,
            :quit                   => Type::Owner }

  Aliases = {  }

  class << self
    def handlers
      @handlers ||= {}
    end

    def on(command, &block)
      handlers[command] = Callback.new(command, block)
    end

    def remove_handlers(*commands)
      commands.each do |command|
        handlers.delete(command)
      end
    end

    def disabled
      @disabled ||= []
    end
  end

  delegate :handlers, :disabled, :to => Command

  def initialize(server, message_type, sender, target, message)
    command, *params = message.split
    command.slice!(0) if command[0, 1] == $config.irc.command_trigger
    channel_id = target == server.config.channel ? server.config.channel_id : server.config.channel_id
    channel    = (target.starts_with?('#') ? target : server.config.channel).downcase
    nickname   = sender.nick
    irc_user   = sender.user
    if command[0, 1] == $config.irc.command_trigger
      unless User[sender.user ? sender.user.username : nickname].access_level >= Type::Admin
        @event = Event.new(server, message_type, sender, target, command, params)
        send_reply "Sorry, you do not have permission to spam the channel."
        return
      end
      command.slice!(0)
      target, sender.nick = sender.nick, channel
    end
    command = command.downcase.to_sym

    # Check for command aliases
    command = Aliases[command] if Aliases.include? command

    commands = Command::Level.merge(Modules.commands)

    # Check if command exists
    return unless commands.include? command

    Modules.each do |name, mod|
      #next unless defined? mod::Commands
      #next unless mod::Commands.include? command
      next unless mod.respond_to? :command_restrictions
      next unless restrictions = mod.command_restrictions[command]
      puts "Processing restrictions: #{restrictions.inspect} server=#{server.name.inspect} channel=#{channel.inspect} command=#{command.inspect} module=#{mod.name}"
      return if restrictions[:servers].present? unless restrictions[:servers].include? server.name
      puts "restrictions[:channels].include?(#{channel.inspect}) ? #{restrictions[:channels].include? channel}"
      return if restrictions[:channels].present? unless restrictions[:channels].include? channel
      break
    end

    @event = Event.new(server, message_type, sender, target, command, params)

    unless handlers.include?(command)
      send_reply "Command not yet implemented! All previous functionality will eventually be rewritten."
      return
    end

    # Check that user is being tracked on irc
    unless irc_user
      puts "[Process command] #{nickname.inspect} does not exist in irc_users -- reporting error to user"
      send_reply "There was an error processing your request. Please try again or report the issue to an administrator."
      return
    end

    puts "[Command] processing [#{command}] for user #{irc_user.username.inspect}..."

    # Check disabled commands
    if disabled.include? command
      send_reply "Command has been disabled by an administrator."
      return
    end

    # Check if user is banned
    if @event.user.access_level == -2
      send_reply "Your account has been suspended."
      return
    elsif @event.user.access_level < 0
      send_reply "You have been banned from using this bot."
      return
    end

    # Check if command access level is higher then users access level
    if commands[command] > @event.user.access_level
      if commands[command] == Type::Registered then
        send_reply "You need to be registered with this bot to use that command."
      else
        send_reply "Your access level is not high enough to use that command."
      end
      return
    end

    # Check if server is missing from identified_on array (caused by User model reloading)
    if irc_user.identified? && irc_user.username.downcase == @event.user.username.downcase
      @event.user.identified_on << server.name unless @event.user.identified_on.include? server.name
    end

    # Check if user is identified
    if @event.user.identified_on.include?(server.name) || commands[command] == Type::Public
      return handle_command(command) unless command == :register
    end
    puts "Not identified to bot on #{server.name}. identified_on: #{@event.user.identified_on.inspect}"
    # Command is not 'identify' and user is not identified to the bot on this server
    server.on_identified_update(nickname) do
      unless irc_user.identified?
        # Nick is not identified to nickserv
        if command == :register
          send_reply "You need to be identified with NickServ in order to register with this bot."
        else
          send_reply "You need to be identified in order to use this bot."
        end
        next
      else
        # Nick is identified to nickserv
        if @event.user.registered? && !@event.user.registered_servers.include?(server.name)
          # User registered on a different server
          send_reply "This account was registered on the [#{@event.user.registered_servers[0]}] IRC server. Please use \"/msg #{server.current_nick} identify <password>\" to manually identify yourself on this server."
          next
        end
        @event.username = @event.irc_user ? @event.irc_user.username : @event.irc_user.nick
      end
      handle_command(command)
    end
    server.request_who(nickname)
  end

  def handle_command(command) #TODO: log exceptions to file
    if $development # reload module if in development mode
      Modules.reload_by_command(command)
      load 'info_board.rb'
    end
    # Process command after reloaded modules have been initialized
    EM.add_timer(0.05) do
      begin
        handlers[command].call(@event)
      rescue Exception => ex
        send_reply "An error occured while processing your command. ",
                   "The exception has been logged and will be looked into by an administrator shortly."
        if @event.user.access_level >= Type::Owner
          send_reply "Exception: #{ex.message}"
          send_reply ex.backtrace.first
          send_reply ex.backtrace.detect {|line| line.starts_with './' } unless ex.backtrace.first.starts_with './'
        end
        puts "[Command] Exception caught in module: #{ex.message}"
        File.open('log/exception.log', 'a') do |file|
          file.puts "[#{Time.now.strftime "%a %d %B %Y %I:%M:%S %p"}] Exception caught in module: #{ex.message}"
          ex.backtrace.each do |line|
            puts line
            file.puts line.sub(File.dirname($0), '.')
          end
          file.puts
        end
      end
    end
  end

  def send_reply(*msgs)
    type = msgs.slice!(0) if msgs.length > 1 and msgs.first.is_a? Symbol
    if @event.target[0, 1] == '#'
      reply_cmd = type || @event.server.config.channel_reply_command || :privmsg
      @event.server.send(reply_cmd, reply_cmd == :notice ? @event.nickname : @event.channel, msgs.join(' '))
    else
      @event.server.send(type || @event.msg_type || :privmsg, @event.nickname, msgs.join(' '))
    end
  end

  # Module commands
  on :modules do
    if Modules.count > 0
      send_reply "Currently loaded modules: #{Modules.loaded.to_sentence}"
      send_reply "Currently unloadable modules: #{Modules.unloadable.to_sentence}" if Modules.unloadable.present?
    else
      send_reply "There are currently no modules loaded."
    end
  end

  on :module do
    unless parameter.count >= 1
      send_reply "Usage: module [un]load <module name>"
      next
    end

    name = parameters
    name = name.sub(" ", "_").camelize if name == name.downcase

    unless Modules.exist? name
      send_reply "Unable to find module file named: #{name.underscore}"
      next
    end

    case payload
      when 'load'
        Modules.unload(name) if defined? name.constantize
        if Modules.load(name)
          send_reply "Loaded module: #{name}"
        else
          send_reply "An error occured while loading module: #{name}"
          if ex = Modules.last_exception
             send_reply "Exception: #{ex.message}"
             send_reply ex.backtrace.first
          end
        end
      when 'unload'
        next send_reply "Module not loaded: #{name}" unless defined? name.constantize
        if Modules.unload(name)
          send_reply "Unloaded module: #{name}"
        else
          send_reply "An error occured while unloading module: #{name}"
        end
      when 'reload'
        if defined? name.constantize
          send_reply "An error occured while unloading module: #{name}" unless Modules.unload(name)
        end
        if Modules.load(name)
          send_reply "Reloaded module: #{name}"
        else
          send_reply "An error occured while reloading module: #{name}"
        end
      when 'status'
        send_error "Unable to find a module with that name." unless Modules.exist? name
        needed_dependencies = Modules.needed_dependencies(name)
        info = "#{"Needed dependencies: #{needed_dependencies.to_sentence}" if needed_dependencies.present?}"
        send_reply "Module is #{Modules.loaded?(name) ? 'loaded' : 'unloadable'}. #{info}"
      when 'dependencies'
        send_error "Unable to find a module with that name." unless Modules.exist? name
        send_reply "Module is dependent on: #{Modules.dependencies(name).to_sentence}"
      else
        send_reply "Usage: module [un]load <module name>"
    end
  end

  on :identstatus do
    unless usr = server.user[payload || nickname]
      send_reply "No info for nickname #{(payload || nickname).inspect} found."
      next
    end

    send_reply "#{usr.nickname}'s identified status: #{usr.identified?}"
  end

  on :say do
    privmsg(payload, parameters)
  end

  on :send do
    send_cmd(payload, *parameter)
  end

  on :quit do
    Core.exit all_params.empty? ? "Shutdown by an administrator." : all_params.join(' ')
  end

  on :restart do
    if all_params.empty?
      Core.restart
    else
      Core.restart all_params.join(' ')
    end
  end

  on :toggle do
    commands = (parameter << payload).collect {|cmd| cmd.downcase.to_sym }.collect {|cmd| Aliases[cmd] || cmd }
    commands = commands.select {|cmd| Command::Level.merge(Modules.commands).include? cmd }
    enabled  = commands.select {|cmd| Command.disabled.include? cmd }
    disabled = commands.reject {|cmd| Command.disabled.include? cmd }
    Command.disabled -= enabled; Command.disabled += disabled
    (reply ||= "") << "#UEnabled commands#U: #{enabled.to_sentence}  " unless enabled.empty?
    (reply ||= "") << "#UDisabled commands#U: #{disabled.to_sentence}" unless disabled.empty?
    reply ||= "Nothing was toggled."
    send_reply reply
  end
end