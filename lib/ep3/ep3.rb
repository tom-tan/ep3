#!/usr/bin/env ruby
require 'optparse'
require_relative 'ep3-init'
require_relative 'ep3-run'
require_relative 'ep3-status'
require_relative 'ep3-list'
require_relative 'ep3-terminate'

if $0 == __FILE__
  parser = OptionParser.new
  parser.banner = <<EOS
Usage: ep3 [options] <command> [<args>]

Commands:
        init          initialize a configuration for a given workflow
        run           run the workflow for a given input
        status        show a status of the workflow
        list          show the output object for the given workflow
        stop          (stop running the workflow)
        resume        (not yet implemented)
        terminate     stop the workflow and remove the configuration
EOS

  parser.order!(ARGV)
  unless ARGV.length >= 1
    puts parser.help
    exit
  end

  cmd = ARGV.shift
  case cmd
  when 'init'      then ep3_init(ARGV)
  when 'run'       then ep3_run(ARGV)
  when 'status'    then ep3_status(ARGV)
  when 'list'      then ep3_list(ARGV)
  when 'stop'      then ep3_stop(ARGV)
  when 'resume'    then ep3_resume(ARGV)
  when 'terminate' then ep3_terminate(ARGV)
  else raise "No such subcommand: #{cmd}"
  end
end
