#!/usr/bin/ruby
begin
  require 'netsoul'
rescue LoadError
  STDERR.puts "Error: #{$!}"
  exit
end

begin
  r = RubySoul::NetSoul.new
  r.start()
rescue
  STDERR.puts "#{$!}"
end
