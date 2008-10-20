#!/usr/bin/ruby -w
begin
  require 'socket'
  require 'readline'
  require 'yaml'
  require 'digest/md5'
  require 'uri'
  require 'thread'
  require 'logger'
  require 'ping'
rescue LoadError
  puts "Error: #{$!}"
  exit
end

RS_APP_NAME = "RubySoul"
RS_VERSION = "3.0.11b"
RS_CONTACT_EMAIL = "christian.kakesa@gmail.com"

class RubySoul
  attr_accessor :socket, :logger
  
  def initialize
    @socket = nil
    @logger = nil
    @socket_num = nil
    @client_host = nil
    @client_port = nil
    @user_from = nil
    @auth_cmd = nil
    @cmd = nil
    @location = nil
    @connect = false
    @state = "server"
    @data = GetConfig()
    @parseThread = nil
    @connectThread = nil
    @mutex = Mutex.new
    @server_timestamp = nil
    @server_timestamp_diff = 0
    @valid_status = ["actif", "away", "idle", "lock"]
    @valid_cmds =       {"send_msg"     => [],
                         "status"       => ["actif", "away", "idle", "lock"],
                         "list"         => ["contacts", "connected_contacts"],
                         "add"          => ["contact"],
                         "del"          => ["contact"],
                         "help"         => [],
                         "?"            => [],
                         "exit"         => [],
                         "quit"         => [],
                         "q"            => []}
    Readline.basic_word_break_characters = ""
    Readline.completion_append_character = nil
    Readline.completion_proc = CompletionProc()
    begin
      ping_res = Ping.pingecho(@data[:server][:host], 1, @data[:server][:port])
    rescue
      puts '/!\ Netsoul server is not reacheable...'
      retry
    end
    Auth(@data[:login], @data[:pass], RS_APP_NAME + " " + RS_VERSION)
    @parseThread = Thread.new do
      @mutex.synchronize do
      	loop do
          ParseCMD()
        end
      end
    end
    PrintInfo()
    puts "[" + Time.now.to_s + "] Started..."
    trap("SIGINT") { puts "\n"; Exit(); }
    trap("SIGTERM") { puts "\n"; Exit(); }
    @connectThread = Thread.new do
      loop do
        Kernel::sleep(1)
        Thread::start()
        if (!@socket || @socket.closed?)
          puts "\nsocket is closed, try to re-auth !!!\n"
          print Prompt()
          @connect = false;
          Auth(@data[:login], @data[:pass], RS_APP_NAME + " " + RS_VERSION)
        end
      end
    end
    #@parseThread.join
    #@onnectedThread.join
    Shell()
  end
  
  def Auth(login, pass, user_ag)
    if not (Connect(login, pass, user_ag))
      puts "Can't connect to the NetSoul server..."
      return false
    else
      @connect = true
      return true
    end
  end
  
  def Connect(login, pass, user_ag)
    if not (@socket)
      @socket = TCPSocket.new(@data[:server][:host], @data[:server][:port])
    end
    if (!@logger and (ARGV[0] == "debug"))
      @logger = Logger.new('logfile.log', 7, 2048000)
    end
    buff = SockGet()
    cmd, @socket_num, md5_hash, @client_host, @client_port, @server_timestamp = buff.split
    @server_timestamp_diff = Time.now.to_i - @server_timestamp.to_i
    reply_hash = Digest::MD5.hexdigest("%s-%s/%s%s" % [md5_hash, @client_host, @client_port, pass])
    @user_from = "ext"
    @auth_cmd = "user"
    @cmd = "cmd"
    @data[:iptable].each do |key, val|
      res = @client_host.match(/^#{val}/)
      if res != nil
        res = "#{key}".chomp
        @location = res
        @user_from = res
        break
      end
    end
    if (@user_from == "ext")
      @auth_cmd = "ext_user"
      @cmd = "user_cmd"
      @location = @data[:location]
    end    
    SockSend("auth_ag ext_user none -")
    ParseCMD()    
    SockSend("ext_user_log " + login + " " + reply_hash + " " + Escape(@location) + " " + Escape(user_ag))
    ParseCMD()
    SockSend("user_cmd attach")
    SockSend("user_cmd state " + @state + ":" +  GetServerTimestamp().to_s)
    return true
  end
  
  def ParseCMD
    buff = SockGet()
    if not (buff.to_s.length > 0)
      SockClose()
      return ""
    end
    cmd = buff.match(/^(\w+)/)[1]
    case cmd.to_s
    when "ping"
      Ping(buff.to_s)
    when "rep"
      Rep(buff)
    when "user_cmd"
      UserCMD(buff)
      return true
    when "exec"
      ServerExec(buff)
      return true
    else
      puts buff.to_s
    end
  end
  
  def Rep(cmd)
    msg_num, msg = cmd.match(/^\w+\ (\d{3})\ \-\-\ (.*)/)[1..2]
    case msg_num.to_s
    when "001"
      ## Command unknown
      return true
    when "002"
      ## Nothing to do, all is right
      return true
    when "003"
      ## Bad number of arguments
      return true
    when "033"
      ## Login or password incorrect
      puts "\nLogin or password incorrect\n"
      print Prompt()
      Exit()
      return false
    end
    return true
  end
  
  def ServerExec(buff)
    #cmd, action = buff.match(/^(\w+)\ (\w+)/)[1..2]
    #if (action.match(/reboot/))
    #  ServerReconnect(60, 3)
    #end
    ## Need to be implemented for the other exec message
    return true
  end

  def UserCMD(user_cmd)
    cmd = user_cmd.match(/^\w+\ \d*:(\w+):.*/)[1]
    case cmd
    when "mail"
      sender, subject = user_cmd.match(/^user_cmd\ [^\ ].*\ \|\ ([^\ ].*)\ \-f\ ([^\ ].*)\ ([^\ ].*)/)[2..3]
      puts "Vous avez recu un email !!!\nDe: " + URI.unescape(sender) + "\nSujet: " + URI.unescape(subject)[1..-2]
      return true
    when "host"
      sender = user_cmd.match(/^user_cmd\ [^\ ].*\ \|\ ([^\ ].*)\ ([^\ ].*)\ ([^\ ].*)/)[2]
      puts "Appel en en cours... !!!\nDe: " + URI.unescape(sender)[1..-1]
      return true
    when "user"
      sender = user_cmd.match(/^user_cmd.*:(.*)@.*/)[1]
      user_info, sub_cmd, msg = user_cmd.match(/^user_cmd\ ([^\ ].*)\ \|\ (\w+)\ (.*)$/)[1..3]
      GetUserResponse(sender, sub_cmd, msg, user_info)
      return true
    else
      puts "[user_cmd] : " + user_cmd + " - This command is not parsed, please contact the developper"
      return false
    end
  end

  def GetUserResponse(sender, sub_cmd, msg, user_info)
    ## puts "[user_info] : " + user_info.split(/:/).to_s
    socket, login, trust_level, login_host, workstation_type, location, group = user_info.split(/:/)
    location = URI.unescape(location)
    ## puts "[socket_id - location] : " + socket_id.to_s + " - " + location.to_s
    case sub_cmd
    when "dotnetSoul_UserTyping"
      #| dotnetSoul_UserTyping null dst=kakesa_c
      #puts "dotnetSoul_UserTyping"
      #puts "[dotnetSoul_UserTyping] : " + sender + " - " + sub_cmd + " - " + msg
      return true
    when "dotnetSoul_UserCancelledTyping"
      #| dotnetSoul_UserCancelledTyping null dst=kakesa_c
      #puts "dotnetSoul_UserCancelledTyping"
      #puts "[dotnetSoul_UserCancelledTyping] : " + sender + " - " + sub_cmd + " - " + msg
      return true
    when "msg"
      #| msg ok dst=kakesa_c
      message, receiver = msg.match(/(.*)\ dst=(.*)/)[1..2]
      puts "\n"
      puts "[MESSAGE]\nFROM: " + sender + "\n" + URI.unescape(message)
      print Prompt()
      $stdout.flush
      return true
    when "who"
      ## For this command fill a @who_cmd data array with parsed data
      ## puts "who msg : " + msg
      #if not (msg.match(/cmd end$/))
      #  socket, login, user_host, login_timestamp, last_status_change_timestamp, trust_level_low, trust_level_high, workstation_type, location, group, status, user_data  = msg.split(/\ /)
      #  status = status.split(/:/)[0]
      #  location = URI.unescape(location)
      #  user_data = URI.unescape(user_data)
      #  if not (@contact.contacts[login.to_s].include?(:state))
      #    @contact.contacts[login.to_s][:state] = Hash.new
      #  end
      #  if not (@contact.contacts[login.to_s][:state].include?(socket.to_i))
      #    @contact.contacts[login.to_s][:state][socket.to_i] = Hash.new
      #  end
      #  @contact.contacts[login.to_s][:state][socket.to_i][:status] = status.to_s
      #  @contact.contacts[login.to_s][:state][socket.to_i][:location] = location.to_s
      #  @user_view.contacts = @contact.contacts
      #  @user_view.fAddUserStatus(login.to_s, socket.to_s, status.to_s)
      #  @s.fLogDebug("[who] : " + sender + " - " + sub_cmd + " - " + msg)
      #end
      return true
    when "state"
      ## puts "state msg : " + msg + " -- " + user_info
      #status = msg.split(/:/)[0]
      #if not (@contact.contacts[sender.to_s].include?(:state))
      #  @contact.contacts[sender.to_s][:state] = Hash.new
      #end
      #if not (@contact.contacts[sender.to_s][:state].include?(socket.to_i))
      #  @contact.contacts[sender.to_s][:state][socket.to_i] = Hash.new
      #end
      #@contact.contacts[sender.to_s][:state][socket.to_i][:status] = status.to_s
      #@contact.contacts[sender.to_s][:state][socket.to_i][:location] = location.to_s
      #@user_view.contacts = @contact.contacts
      #@user_view.fUpdateUserStatus(sender.to_s, socket.to_s, status.to_s)
      puts "[state] : " + sender + " " + status.to_s
      return true
    when "login"
      ## puts "login msg : " + msg + " -- " + user_info
      puts "[login] : " + sender
      return true
    when "logout"
      ## puts "logout msg : " + msg
      ## TODO build a function to udate user data in C_Contact.rb
      #if (@contact.contacts[sender.to_s].include?(:state))
      #  @contact.contacts[sender.to_s][:state].delete(socket.to_i)
      #end
      #@user_view.contacts = @contact.contacts
      #@user_view.fDelUserStatus(sender.to_s, socket.to_s, sub_cmd.to_s)
      puts "[logout] : " + sender
      return true
    else
      ## puts "sub_cmd not reconize in fGetUserResponse : " + sub_cmd
      puts "[unknown sub command] : " + sender + " - " + sub_cmd + " - " + msg
      return false
    end
  end

  def Ping(cmd)
    SockSend(cmd.to_s)
  end
  
  def GetConfig(filename = File.dirname(__FILE__) + "/config.yml")
    config = YAML::load(File.open(filename));
    return config
  end
  
  def SockSend(string)
    if (@socket)
      @socket.puts string
      if (@logger)
        @logger.debug "[send] : " + string
      end
    end
  end
  
  def SockGet
    if (@socket)
      response = @socket.gets.to_s.chomp
      if (@logger)
        @logger.debug "[gets] : " + response
      end
      return response
    end
  end
  
  def SockClose
    if not (@socket.nil?)
      @socket.puts "exit"
      @socket.close
    end
  end
  
  def Exit
    at_exit do
      if (@socket); SockClose() end;
      if (@logger); @logger.close end;
      if (@parseThread.alive?); @parseThread.kill!  end;
      if (@connectThread.alive?); @connectThread.kill! end;
    end
    exit(0)
  end
  
  def Escape(str)
    str = URI.escape(str)
    res = URI.escape(str, "\ :'@~\[\]&()=*$!;,\+\/\?")
    return res
  end
  
  def Prompt
    return "rubysoul#> "
  end

  def Shell
    loop do
      msg = Readline.readline(Prompt().to_s)
      msg.chomp!
      Readline::HISTORY.push(msg) if (msg.length > 0)
      if (msg == "?" || msg == "help")
        Help()
      elsif (msg == "credits")
        Credits()
      elsif (msg == "exit" || msg == "quit" || msg == "q")
        Exit()
        puts "\n"
      else ## Parse complexe command line
        if (msg.split(":").length >= 2)
          case (msg.split(":")[0])
          when "send_msg"
            SockSend("user_cmd msg_user {" + msg.split(":")[1].gsub(/ /, ",") + "} msg " + Escape(msg.split(":", 3)[2]))
          when "status"
            if @valid_status.include?(msg.split(":")[1])
              Status(msg.split(":")[1])
            end
          else
            puts "command not found! type 'help' for more info." if (msg.length > 0)
          end
        else
          puts "command not found! type 'help' for more info." if (msg.length > 0)
        end
      end
    end
  end

  def Help
    puts "*******************************************************************************"
    puts "* [CMD]      : help - status:actif,away,idle,lock - exit,quit,q - credits     *"
    puts "* [SEND_MSG] : send_msg:login_1 login_2 login_3:your message with : if u want *"
    puts "* [LIST]     : list:user                                                      *"
    puts "* [ADD]      : add:user                                                       *"
    puts "* [DEL]      : del:user                                                       *"
    puts "*******************************************************************************"
  end

  def Credits
    puts "*********************************************************************************"
    puts "* Developpers  : Christian KAKESA etna_2008(paris) <christian.kakesa@gmail.com> *"
    puts "* Contributors : Yannick BATTAIL epitech_2010(lyon)                             *"
    puts "*********************************************************************************"
  end

  def Status(status)
    ts = GetServerTimestamp().to_s
    SockSend("user_cmd state " + status + ":" + ts)
    puts "user_cmd state " + status + ":" + ts
    puts "status changed to " + status
  end

  def List
    puts "list not yet implemented"
  end
  
  def PrintInfo
    puts '*************************************************'
    puts '* ' + RS_APP_NAME + ' V' + RS_VERSION + ' : with Shell capability     *'
    puts '*************************************************'
  end

  def GetServerTimestamp
    return Time.now.to_i - @server_timestamp_diff.to_i
  end

  def CompletionProc
    proc do |input|
      line = input
      if (input.to_s.empty?)
        puts "\n"
        @valid_cmds.each do |k, v|
          print k.to_s + " "
        end
      elsif (input.to_s == "status")
        puts "\n"
        @valid_cmds["status"].each do |v|
          print ":" + v.to_s + " "
        end
      elsif (input.to_s == "list")
        puts "\n"
        @valid_cmds["list"].each do |v|
          print ":" + v.to_s + " "
        end
      elsif (input.to_s == "add")
        puts "\n"
        @valid_cmds.each do |v|
          print ":" + v.to_s + " "
        end
      elsif (input.to_s == "del")
        puts "\n"
        @valid_cmds.each do |v|
          print ":" + v.to_s + " "
        end
      end
      puts "\n"
      print Prompt() + line
    end
  end
end

begin
  rss = RubySoul.new
rescue IOError, Errno::ENETRESET, Errno::ESHUTDOWN, Errno::ETIMEDOUT, Errno::ECONNRESET, Errno::ENETDOWN, Errno::EINVAL, Errno::ECONNABORTED, Errno::EIO, Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::EFAULT, Errno::EHOSTUNREACH, Errno::EINTR, Errno::EBADF, Errno::EPIPE
  puts "Error: #{$!}"
  Kernel::sleep(5)
  retry
rescue
  puts "Error: #{$!}"
  exit(1)
end
