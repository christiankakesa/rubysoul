begin
  require 'uri'
rescue LoadError
  puts "Error: #{$!}"
  exit
end

module RubySoul
  def self.print_info
    puts '*************************************************'
    puts '* ' + RubySoul::APP_NAME + ' V' + RubySoul::VERSION + ' *'
    puts '*************************************************'
  end

  def self.help
    puts "******************************************************************************"
    puts "* [commands]          : help - exit,quit,q - credits,credit                  *"
    puts "* [state]             : state:actif,away,idle,lock                           *"
    puts "* [send message]      : send_msg:login_1 login_2 login_3:your message        *"
    puts "* [list]              : list:contacts, list:connected_contacts               *"
    puts "* [add]               : add:user:login_1 login_2 login_3                     *"
    puts "* [del]               : del:user:login_1 login_2 login_3                     *"
    puts "******************************************************************************"
  end

  def self.credits
    puts "*********************************************************************************"
    puts "* Developpers  : Christian KAKESA etna_2008(paris) <christian.kakesa@gmail.com> *"
    puts "* Contributors : Yannick BATTAIL epitech_2010(lyon)                             *"
    puts "*********************************************************************************"
  end

  def self.print_command_not_found
    puts "command not found! type 'help' for more information."
  end

  def self.escape(str)
    str = URI.escape(str)
    URI.escape(str, "\ :'@~\[\]&()=*$!;,\+\/\?")
  end

  def self.ltrim(str)
    return str.gsub(/^\s+/, '')
  end

  def self.rtrim(str)
    return str.gsub(/\s+$/, '')
  end

  def self.trim(str)
    str = RubySoul::ltrim(str)
    str = RubySoul::rtrim(str)
    return str
  end
end #--- | module NetSoul
