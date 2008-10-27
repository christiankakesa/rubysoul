#!/usr/bin/ruby -w
begin
  require 'netsoul'
rescue LoadError
  puts "Error: #{$!}"
  exit
end

begin
  r = RubySoul::NetSoul.new
  r.start()
rescue
  puts "#{$!}"
end
