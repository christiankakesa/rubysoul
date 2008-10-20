begin
  require 'uri'
rescue LoadError
  puts "Error: #{$!}"
  exit
end

module RubySoul
  def escape(str)
    str = URI.escape(str)
    URI.escape(str, "\ :'@~\[\]&()=*$!;,\+\/\?")
  end
end #--- | module NetSoul
