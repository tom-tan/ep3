#!/usr/bin/env ruby

if $0 == __FILE__
  unless ARGV.length == 1
    puts "Usage: #{$0} command"
    exit
  end
  cmd = ARGV.first
  pid = fork do
    Process.setpgrp
    exec(cmd)
  end

  Process.waitall
end
