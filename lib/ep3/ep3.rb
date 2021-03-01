#!/usr/bin/env ruby
require 'optparse'
require_relative 'ep3-init'
require_relative 'ep3-run'
require_relative 'ep3-list'
require_relative 'ep3-hook'

if $0 == __FILE__
  parser = OptionParser.new
  parser.banner = <<EOS
Usage: ep3 [options] <command> [<args>]

Commands:
        init          initialize a configuration for a given workflow
        run           run the workflow for a given input
        list          show the output object for the given workflow
        hook          apply extensions to Petri Nets for a given workflow
        resume        (not yet implemented)
EOS

  parser.order!(ARGV)
  unless ARGV.length >= 1
    puts parser.help
    exit
  end

  cmd = ARGV.shift
  exit case cmd
       when 'init'      then ep3_init(ARGV)
       when 'run'       then ep3_run(ARGV)
       when 'list'      then ep3_list(ARGV)
       when 'hook'      then ep3_hook(ARGV)
       when 'resume'    then ep3_resume(ARGV)
       else raise "No such subcommand: #{cmd}"
       end
end
