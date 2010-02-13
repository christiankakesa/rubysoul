begin
  require 'uri'
rescue LoadError
  STDERR.puts "Error: #{$!}"
  exit
end

module RubySoul
  def self.msg_info
    str  = "*************************************************\n"
    str += "* ' + RubySoul::APP_NAME + ' V' + RubySoul::VERSION + ' *\n"
    str += "*************************************************\n"
    str
  end

  def self.msg_help
    str  = "*******************************************************************************\n"
    str += "* [helpers]           : help,? - exit,quit,q - credits,credit                 *\n"
    str += "* [state]             : state:actif,away,idle,lock                            *\n"
    str += "* [show]              : show:state, show:config                               *\n"
    str += "* [set config]        : config:login:my_login, socks_password, unix_password, *\n"
    str += "*                       state, location, user_group, system                   *\n"
    str += "* [send message]      : send_msg:login_1 login_2 login_3:your message         *\n"
    str += "* [list]              : list:contacts, list:connected_contacts                *\n"
    str += "* [add]               : add:contcats:login_1 login_2 login_3                  *\n"
    str += "* [del]               : del:contacts:login_1 login_2 login_3                  *\n"
    str += "*******************************************************************************\n"
    str
  end

  def self.msg_credits
    str  = "*********************************************************************************\n"
    str += "* Developpers  : Christian KAKESA etna_2008(paris) <christian.kakesa@gmail.com> *\n"
    str += "*********************************************************************************\n"
    str
  end

  def self.msg_command_not_found
    return "command not found! type 'help' for more information."
  end

    def self.prompt
      "rubysoul#> "
    end

  def self.escape(str)
    str = URI.escape(str)
    URI.escape(str, "\ :'@~\[\]&()=*$!;,\+\/\?")
    str
  end

  def self.ltrim(str)
    str.gsub(/^\s+/, '')
  end

  def self.rtrim(str)
    str.gsub(/\s+$/, '')
  end

  def self.trim(str)
    str = RubySoul::ltrim(str)
    str = RubySoul::rtrim(str)
    str
  end
end #--- | module NetSoul
