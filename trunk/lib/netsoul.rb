begin
  require 'socket'
  require 'readline'
  require 'yaml'
  require 'uri'
  require 'digest/md5'
  require 'thread'
  require 'logger'
rescue LoadError
  puts "Error: #{$!}"
end

module RubySoul
  APP_NAME = "RubySoul"
  VERSION = "3.1.00b"
  CONTACT_EMAIL = "Christian KAKESA <christian.kakesa@gmail.com>"

class NetSoul
  @connected = false
  @connected_mutex = nil
  @data = nil
  @host = nil
  @port = nil
  @socket = nil
  @shell = nil
  def initialize
    @mutex = Mutex.new
    get_data()
    @host = "ns-server.epita.fr"
    @port = 4242
    @shell = Shell.new
  end

  def get_data
    @data = Hash.new
    @data[:config] = get_config()
    @data[:contacts] = get_contacts()
    @data[:locations] = get_locations()    
  end

  def login
    begin
      @socket = TCPSocket.new @host, @port
    rescue
      puts "Error: #{$!}"
      @connected_mutex.synchronize do
        @connected = false
      end
      sleep(3)
      retry
    end
    buf = @socket.gets.strip
    cmd, @socket_num, md5_hash, @client_host, @client_port, @server_timestamp = buf.split
    @server_timestamp_diff = Time.now.to_i - @server_timestamp.to_i
    reply_hash = Digest::MD5.hexdigest("%s-%s/%s%s" % [md5_hash, @client_host, @client_port, @data[:config][:pass]])
    @user_from = "ext"
    @auth_cmd = "user"
    @user_cmd = "cmd"
    @data[:locations][:iptable].each do |key, val|
      res = @client_host.match(/^#{val}/)
      if res
        res = "#{key}".chomp
        @location = res
        @user_from = res
        break
      end
    end
    if (@user_from == "ext")
      @auth_cmd = "ext_user"
      @user_cmd = "user_cmd"
      @location = @data[:config][:location]
    end
    @socket.puts "auth_ag " + @auth_cmd + " none -"
    exit if not server_rep(@socket.gets.strip)
    @socket.puts @auth_cmd + "_log " + @data[:config][:login] + " " + reply_hash + " " + RubySoul::escape(@location) + " " + RubySoul::escape(RubySoul::APP_NAME)
    exit if not server_rep(@socket.gets.strip)
    @socket.puts @user_cmd + " attach"
    @socket.puts @user_cmd + " state " + @data[:config][:status] + ":" +  get_server_timestamp().to_s
  end
  
  def start
    login()
    recv()
    @shell.start()
  end

  def stop
    logout()
    exit
  end

  def logout
    if @socket; @socket.puts("exit"); @socket.close; end;
    @socket = nil
  end

  def reconnect
    logout()
    login()
  end

  def recv
    Thread.new do
      loop do
        begin
          ns_parser(@socket.gets.strip) #--- | test with chomp or strip in order to cath the good error
        rescue
          @connected_mutex.synchronize do
            @connected = false
          end
          reconnect()
        end
      end
    end
  end

  def send(data)
    @socket.puts data
  end

  def ns_parser(line)
    #--- | implementation of the netsoul server commands.
    cmd = line.match(/^(\w+)/)[1]
    case cmd
    when "ping"
      server_ping(line)
    when "rep"
      server_rep(line)
    when "user_cmd"
      server_user_cmd(line)
      return true
    when "exec"
      server_exec(line)
      return true
    else
      puts line
    end
  end

  def server_ping(line)
    @socket.puts line
  end

  def server_rep(line)
    msg_num, msg = line.match(/^\w+\ (\d{3})\ \-\-\ (.*)/)[1..2]
    case msg_num.to_s
    when "001"
      puts "Command unknown"
    when "002"
      ## Nothing to do, all is right
      return true
    when "003"
      puts "Bad number of arguments"
    when "033"
      puts "Login or password incorrect\n"
    end
    puts "server_rep: " + line
    return false
  end

  def server_user_cmd(line)

  end

  def server_exec(line)

  end

  def get_config
    YAML::load_file("conf/config.yml")
  end

  def get_contacts
    YAML::load_file("conf/contacts.yml")
  end

  def get_locations
    YAML::load_file("conf/locations.yml")
  end

  def get_server_timestamp
    Time.now.to_i - @server_timestamp_diff.to_i
  end
end #--- | Class NetSoul

class Shell
  def initialize
    shell_init()
  end

  def shell_init
    @valid_status = ["actif", "away", "idle", "lock"]
    @valid_cmds =
      {"send_msg"     => [],
      "status"       => ["actif", "away", "idle", "lock"],
      "list"         => ["contacts", "connected_contacts"],
      "add"          => ["contact"],
      "del"          => ["contact"],
      "help"         => [],
      "?"            => [],
      "exit"         => [],
      "bye"          => [],
      "quit"         => [],
      "q"            => []}
    Readline.basic_word_break_characters = ""
    Readline.completion_append_character = nil
    Readline.completion_proc = completion_proc()
  end

  def start
    loop do
      msg = Readline.readline(prompt().to_s)
      msg.chomp!
      Readline::HISTORY.push(msg) if (msg.length > 0)
      if (msg == "?" || msg == "help")
        help()
      elsif (msg == "credits")
        credits()
      elsif (msg == "exit" || msg == "bye" || msg == "q")
        bye()
        puts "\n"
      else ## Parse complexe command line
        if (msg.split(":").length >= 2)
          case (msg.split(":")[0])
          when "send_msg"
            sock_send("user_cmd msg_user {" + msg.split(":")[1].gsub(/ /, ",") + "} msg " + escape(msg.split(":", 3)[2]))
          when "status"
            if @valid_status.include?(msg.split(":")[1])
              status(msg.split(":")[1])
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

  def prompt
    "rubysoul#> "
  end

  def completion_proc 
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
      print prompt() + line
    end
  end
end #--- | Class Shell

def self.print_info
  puts '*************************************************'
  puts '* ' + RubySoul::APP_NAME + ' V' + RubySoul::VERSION + ' *'
  puts '*************************************************'
end

def self.help
  puts "*******************************************************************************"
  puts "* [CMD]      : help - status:actif,away,idle,lock - exit,quit,q - credits     *"
  puts "* [SEND_MSG] : send_msg:login_1 login_2 login_3:your message with : if u want *"
  puts "* [LIST]     : list:user                                                      *"
  puts "* [ADD]      : add:user                                                       *"
  puts "* [DEL]      : del:user                                                       *"
  puts "*******************************************************************************"
end

def self.credits
  puts "*********************************************************************************"
  puts "* Developpers  : Christian KAKESA etna_2008(paris) <christian.kakesa@gmail.com> *"
  puts "* Contributors : Yannick BATTAIL epitech_2010(lyon)                             *"
  puts "*********************************************************************************"
end

def self.escape(str)
  str = URI.escape(str)
  URI.escape(str, "\ :'@~\[\]&()=*$!;,\+\/\?")
end

end #--- | module
