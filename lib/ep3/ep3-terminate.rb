#!/usr/bin/env ruby
# coding: utf-8
require 'optparse'
require 'fileutils'

def ep3_terminate(args)
  parser = OptionParser.new
  parser.banner = "Usage: ep3 terminate [options]"
  parser.on('--target-dir=DIR')
  parser.on('--leave-tmpdir')

  opts = parser.getopts(args)

  unless args.empty?
    puts parser.help
    exit
  end
  dir = if opts.include? 'target-dir'
          opts['target-dir']
        else
          raise '--target-dir is needed'
        end
  unless Dir.exist? dir
    raise "Directory not found: #{dir}"
  end

  unless File.exist? File.join(dir, 'ep3', 'control')
    raise 'Directory not found: control'
  end

  open(File.join(dir, 'ep3', 'control'), 'w') { |f|
    f.puts 'stop'
  }

  unless opts.include? 'leave-tmpdir'
    FileUtils.remove_entry dir
  end
end

if $0 == __FILE__
  ep3_terminate(ARGV)
end
