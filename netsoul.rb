begin
  require 'socket'
  require 'readline'
  require 'yaml'
  require 'uri'
  require 'digest/md5'
  require 'thread'
  require 'logger'
  require 'utils'
rescue LoadError
  puts "Error: #{$!}"
end

module RubySoul
  APP_NAME = "RubySoul"
  VERSION = "3.2.50"
  CONTACT_EMAIL = "Christian KAKESA <christian.kakesa@gmail.com>"

  class NetSoul
    @connected = false
    @mutex_connected = nil
    @mutex_send = nil
    @thread_recv = nil
    @data = nil
    @host = nil
    @port = nil
    @current_state = nil
    @socket = nil
    @shell = nil

    attr_reader	:current_state
    attr_accessor	:data

    def initialize
      @mutex_connected = Mutex.new
      @mutex_send = Mutex.new
      @host = "ns-server.epita.fr"
      @port = 4242
      @shell = Shell.new(self)
      get_conf_data()
      trap("SIGINT") { stop(); exit; }
      trap("SIGTERM") { stop(); exit; }
    end

    def get_conf_data
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
        @mutex_connected.synchronize do
          @connected = false
        end
        sleep(3)
        retry
      end
      buf = @socket.gets.strip
      cmd, @socket_num, md5_hash, @client_host, @client_port, @server_timestamp = buf.split
      @server_timestamp_diff = Time.now.to_i - @server_timestamp.to_i
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
      if @user_from.eql?("ext")
        @auth_cmd = "ext_user"
        @user_cmd = "user_cmd"
        @location = @data[:config][:location]
      end
      send("auth_ag " + @auth_cmd + " none -")
      exit if not ns_parser(@socket.gets.strip)
      if @data[:config][:unix_password].length > 0
        begin
          require 'lib/kerberos/NsToken'
        rescue LoadError
          puts "Error: #{$!}"
          puts "Build the \"NsToken\" ruby/c extension if you don't.\nSomething like this : \"cd ./lib/kerberos && ruby extconf.rb && make\""
          exit
        end
        tk = NsToken.new
        if not tk.get_token(@data[:config][:login], @data[:config][:unix_password])
          puts "Impossible to retrieve the kerberos token"
          exit
        end
        send("#{@auth_cmd}_klog #{tk.token_base64} #{RubySoul::escape(@data[:config][:system])} #{RubySoul::escape(@location)} #{RubySoul::escape(@data[:config][:user_group])} #{RubySoul::escape(RubySoul::APP_NAME+" "+RubySoul::VERSION)}")
      else
        reply_hash = Digest::MD5.hexdigest("%s-%s/%s%s" % [md5_hash, @client_host, @client_port, @data[:config][:socks_password]])
        send("#{@auth_cmd}_log #{@data[:config][:login]} #{reply_hash} #{RubySoul::escape(@location)} #{RubySoul::escape(RubySoul::APP_NAME+" "+RubySoul::VERSION)}")
      end
      exit if not ns_parser(@socket.gets.strip)
      @mutex_connected.synchronize do
        @connected = true
      end
      ns_attach()
      ns_state(@data[:config][:state]) if @data[:config][:state].length > 0
      ns_who(@data[:contacts].keys.join(',')) if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
      ns_watch_log_user(@data[:contacts].keys.join(',')) if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
      recv()
    end

    def start
      login()
      @shell.start()
    end

    def stop(line_feed = true)
      logout()
      puts "\n" if line_feed
      exit
    end

    def logout
      if !@thread_recv.nil? && @thread_recv.alive?
        @thread_recv.kill!
        @thread_recv = nil
      end
      if @socket
        send("exit")
        @socket.close
      end
      @socket = nil
    end

    #--- | Must be private, because just called once
    def recv
      @thread_recv = Thread.new do
        loop do
          begin
            ns_parser(@socket.gets.strip) #--- | test with chomp or strip in order to cath the good error
          rescue
            @mutex_connected.synchronize do
              @connected = false
            end
            exit
          end
        end
      end
    end

    def send(data)
      @mutex_send.synchronize do
        @socket.puts data
      end
    end

    def ns_parser(line)
      #--- | implementation of the netsoul server commands.
      # puts line
      cmd = RubySoul::trim(line.split(' ')[0])
      case cmd
      when "ping"
        ns_recv_ping(line)
      when "rep"
        ns_recv_rep(line)
      when "user_cmd"
        ns_recv_user_cmd(line)
        return true
      when "exec"
        ns_recv_exec(line)
        return true
      else
        puts line
      end
    end

    def ns_recv_ping(line)
      @socket.puts "ping 42"
    end

    def ns_recv_rep(line)
      msg_num = line.split(' ')[1]
      case msg_num.to_s
      when "001"
        puts "Command unknown"
      when "002"
        ## Nothing to do, all is right
        return true
      when "003"
        puts "Bad number of arguments"
      when "033"
        puts "Login or password incorrect"
      when "140"
        puts "User identification failed"
      else
        puts "ns_rep: " + line
      end
      return false
    end

    def ns_recv_user_cmd(line)
      cmd, user	= RubySoul::trim(line.split('|')[0]).split(' ')
      response	= RubySoul::trim(line.split('|')[1])
      sub_cmd	= RubySoul::trim(user.split(':')[1])
      case sub_cmd
      when "mail"
        email_sender, email_subject = response.split(' ')[2..3]
        puts "Vous avez reçu un email !!!\nDe: " + URI.unescape(email_sender) + "\nSujet: " + URI.unescape(email_subject)
        return true
      when "host"
        tel_sender = response.split(' ')[2]
        puts "Appel en en cours... !!!\nDe: " + URI.unescape(tel_sender)
        return true
      when "user"
        ns_get_user_response(cmd, user, response)
        return true
      else
        puts "[user_cmd] : " + line + " - This command line is not parsed, please contact the developper"
        return false
      end
    end

    def ns_get_user_response(cmd, user, response) # private method
      sub_cmd = response.split(' ')[0]
      case sub_cmd
      when "login"
        ns_who(@data[:contacts].keys.join(',')) if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
        return
      when "logout"
        ns_who(@data[:contacts].keys.join(',')) if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
        return
      when "state"
        return
      when "who"
        if @data[:contacts].is_a?(Hash) && @data[:contacts].include?(response.split(' ')[2].to_sym)
          @data[:contacts][response.split(' ')[2].to_sym][response.split(' ')[1].to_sym] = true
        end
        return
      when "msg"
        puts "\n"
        puts "[Message from: #{user.split(":")[3].split('@')[0]}]"
        puts URI.unescape(response.split(' ')[1])
        puts "----------"
        print RubySoul::prompt()
        $stdout.flush()
        return
      end
    end


    def ns_recv_exec(line)
      puts "[exec] Not yep implemented !!!"
    end

    def ns_attach
      send(@user_cmd + " attach")
    end

    def ns_state(state)
      send(@user_cmd + " state " + state.to_s + ":" +  get_server_timestamp().to_s)
      @current_state = state
    end

    def ns_send_msg(users, msg)
      send(@user_cmd + " msg_user {" + users.to_s + "} msg " + msg)
    end

    def ns_who(users)
      if @data[:contacts].is_a?(Hash)
        @data[:contacts].each do |u, v|
          @data[:contacts][u] = {}
        end
      end
      send(@user_cmd + " who {" + users.to_s + "}")
    end

    def ns_watch_log_user(users)
      send(@user_cmd + " watch_log_user {" + users.to_s + "}")
    end

    def get_config
      YAML::load_file("conf/config.yml")
    end

    def save_config
      File.open("conf/config.yml", "w") {|file| file.puts(@data[:config].to_yaml.to_s); file.close;}
    end

    def get_contacts
      YAML::load_file("conf/contacts.yml")
    end

    def save_contacts
      File.open("conf/contacts.yml", "w") {|file| file.puts(@data[:contacts].to_yaml.to_s); file.close;}
    end

    def add_contacts(users)
      tmp_users = users.to_s.split(' ')
      tmp_users.each do |user|
        user.gsub!(/\s/, '')
        if @data[:contacts].is_a?(Hash)
          @data[:contacts][user.to_sym] = {}
        else
          @data[:contacts] = Hash.new
          @data[:contacts][user.to_sym] = {}
        end
      end
      ns_who(@data[:contacts].keys.join(',')) if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
      ns_watch_log_user(@data[:contacts].keys.join(',')) if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
      save_contacts()
    end

    def add_user(users) # don't use alias for lisibility
      add_contacts(users)
    end

    def del_contacts(users)
      tmp_users = users.to_s.split(' ')
      tmp_users.each do |user|
        user.gsub!(/\s/, '')
        if @data[:contacts].include?(user.to_sym)
          @data[:contacts].delete(user.to_sym)
        else
          puts "User \"#{user}\" not found in contact list"
        end
      end
      ns_who(@data[:contacts].keys.join(',')) if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
      ns_watch_log_user(@data[:contacts].keys.join(',')) if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
      save_contacts()
    end

    def del_user(users) # don't use alias for lisibility
      del_contacts(users)
    end

    def list_contacts()
      if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
        puts '#--- | Contact list'
        @data[:contacts].keys.each do |user|
          puts user.to_s
        end
      else
        puts "No contacts in contact list"
      end
      return
    end

    def list_connected_contacts()
      if @data[:contacts].is_a?(Hash) && @data[:contacts].length > 0
        puts '#--- | Connected contact list'
        found_one = false
        @data[:contacts].each do |user, sessions|
          if sessions.length > 0
            puts user.to_s
            found_one = true
          end
        end
        if not found_one
          puts "No contact connected !!!"
        end
      end
      return
    end

    def get_locations
      YAML::load_file("conf/locations.yml")
    end

    def get_server_timestamp
      Time.now.to_i - @server_timestamp_diff.to_i
    end
  end #--- | class NetSoul

  class Shell
    def initialize(ns_object)
      @ns = ns_object
      shell_init()
    end

    def shell_init
      @valid_cmds =
      { "send_msg" => [],
        "state"    => ["actif", "away", "idle", "lock"],
        "show"     => ["state", "config"],
        "config"   => ["login", "socks_password", "unix_password", "state", "location", "user_group", "system"],
        "list"     => ["contacts", "connected_contacts"],
        "add"      => ["contacts"],
        "del"      => ["contacts"],
        "help"     => [],
        "?"        => [],
        "exit"     => [],
        "bye"      => [],
        "quit"     => [],
        "q"        => []
      }
      Readline.basic_word_break_characters = ""
      Readline.completion_append_character = nil
      Readline.completion_proc = completion_proc()
    end

    def start
      loop do
        @rd_msg = Readline.readline(prompt().to_s)
        msg = @rd_msg
        msg.chomp!
        Readline::HISTORY.push(msg) if (msg.length > 0)
        if (msg == "?" || msg == "help")
          RubySoul::help()
        elsif (msg == "credits" || msg == "credit")
          RubySoul::credits()
        elsif (msg == "exit" || msg == "bye" || msg == "q" || msg == "quit")
          @ns.stop(false)
        else ## Parse complexe command line
          if (msg.split(":").length >= 2)
            case (msg.split(":")[0])
            when "send_msg"
              @ns.ns_send_msg(msg.split(":")[1].gsub(/ /, ","), RubySoul::escape(msg.split(":", 3)[2]))
            when "state"
              if @valid_cmds["state"].include?(msg.split(":")[1])
                @ns.ns_state(msg.split(":")[1])
              else
                puts "Command #{msg.split(":")[1]} not allowed"
              end
            when "show"
              case msg.split(":")[1]
              when "state"
                puts "Your current state is \"#{@ns.current_state}\""
              when "config"
                puts @ns.data[:config].to_yaml.to_s
              else
                RubySoul::print_command_not_found()
              end
            when "config"
              found = case msg.split(":")[1]
              when "login"
                @ns.data[:config][:login] = msg.split(":")[2] if msg.split(":").length == 3
              when "socks_password"
                @ns.data[:config][:socks_password] = msg.split(":")[2] if msg.split(":").length == 3
              when "unix_password"
                @ns.data[:config][:unix_password] = msg.split(":")[2] if msg.split(":").length == 3
              when "state"
                if not @valid_cmds["state"].include?(msg.split(":")[2])
                  puts "State is not valid. Valid states are : #{@valid_cmds["state"].join(", ")}"
                  false
                else
                  @ns.data[:config][:state] = msg.split(":")[2] if msg.split(":").length == 3
                end
              when "location"
                @ns.data[:config][:location] = msg.split(":")[2] if msg.split(":").length == 3
              when "user_group"
                @ns.data[:config][:user_group] = msg.split(":")[2] if msg.split(":").length == 3
              when "system"
                @ns.data[:config][:system] = msg.split(":")[2] if msg.split(":").length == 3
              else
                RubySoul::print_command_not_found()
                false
              end
              @ns.save_config() if found
            when "list"
              case msg.split(":")[1]
              when "contacts"
                @ns.list_contacts()
              when "connected_contacts"
                @ns.list_connected_contacts()
              else
                RubySoul::print_command_not_found()
              end
            when "add"
              case msg.split(":")[1]
              when "contacts"
                @ns.add_user(msg.split(":")[2]) if msg.split(":").length == 3
              else
                RubySoul::print_command_not_found()
              end
            when "del"
              case msg.split(":")[1]
              when "contacts"
                @ns.del_user(msg.split(":")[2]) if msg.split(":").length == 3
              else
                RubySoul::print_command_not_found()
              end
            else
              RubySoul::print_command_not_found() if (msg.length > 0)
            end
          else
            RubySoul::print_command_not_found() if (msg.length > 0)
          end
        end
      end
    end

    def prompt
      RubySoul::prompt()
    end

    def completion_proc
      proc do |input|
        line = input
        if (input.to_s.empty?)
          puts "\n"
          @valid_cmds.each do |k, v|
            print k.to_s + " "
          end
        elsif (input.to_s == "state" || input.to_s == "state:")
          puts "\n"
          @valid_cmds["state"].each do |v|
            print input.to_s.include?(":") ? v.to_s + " " : ":" + v.to_s + " "
          end
        elsif (input.to_s == "show" || input.to_s == "show:")
          puts "\n"
          @valid_cmds["show"].each do |v|
            print input.to_s.include?(":") ? v.to_s + " " : ":" + v.to_s + " "
          end
        elsif (input.to_s == "config" || input.to_s == "config:")
          puts "\n"
          @valid_cmds["config"].each do |v|
            print input.to_s.include?(":") ? v.to_s + " " : ":" + v.to_s + " "
          end
        elsif (input.to_s == "list" || input.to_s == "list:")
          puts "\n"
          @valid_cmds["list"].each do |v|
            print input.to_s.include?(":") ? v.to_s + " " : ":" + v.to_s + " "
          end
        elsif (input.to_s == "add" || input.to_s == "add:")
          puts "\n"
          @valid_cmds["add"].each do |v|
            print input.to_s.include?(":") ? v.to_s + " " : ":" + v.to_s + " "
          end
        elsif (input.to_s == "del" || input.to_s == "del:")
          puts "\n"
          @valid_cmds["del"].each do |v|
            print input.to_s.include?(":") ? v.to_s + " " : ":" + v.to_s + " "
          end
        end
        puts "\n"
        print prompt() + line
      end
    end
  end #--- | class Shell

end #--- | module

