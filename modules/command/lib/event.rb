class Command
  class Event
    attr_accessor :server, :msg_type, :channel_id, :channel, :nickname, :irc_user, :target,
                  :command, :payload, :parameter, :parameters, :all_params, :username, :user

    def initialize(server, message_type, sender, target, command, params)
      @server     = server
      @channel_id = target == server.config.channel ? server.config.channel_id : server.config.channel_id
      @channel    = target.starts_with?('#') ? target : server.config.channel
      @msg_type   = message_type
      @nickname   = sender.nick
      @irc_user   = sender.user
      @username   = sender.user ? sender.user.username : sender.nick 
      @target     = target
      @command    = command
      @all_params = params
      @payload    = params.first || nil
      @parameter  = params[1..-1] || []
      @parameters = @parameter.join ' '
      @user       = User[@username]
    end

    def channel?
      @target[0] == '#'
    end

    def parameters?
      !@parameter.empty?
    end
  end
end