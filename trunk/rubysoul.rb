#!/usr/bin/ruby -w
begin
  require 'lib/netsoul'
rescue LoadError
  puts "Error: #{$!}"
  exit
end

r = RubySoul::NetSoul.new
r.start()
