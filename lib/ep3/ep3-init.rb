#!/usr/bin/env ruby
# coding: utf-8
require 'optparse'
require 'tmpdir'
require 'fileutils'
require_relative 'init/cwl2wfnet'
require_relative 'init/wfnet2entr'
require_relative 'runtime/inspector'
require_relative 'init/wfnet2medal'

def ep3_init(args)
  parser = OptionParser.new
  parser.banner = "Usage: ep3 init [options] <cwl>"
  parser.on('--target-dir=DIR')
  parser.on('--force')
  parser.on('--print-dot')
  opts = parser.getopts(args)

  unless args.length == 1
    puts parser.help
    exit
  end

  unless ENV.include? 'EP3_TEMPLATE_DIR'
    raise 'EP3_TEMPLATE_DIR is necessary'
  end
  template_dir = ENV['EP3_TEMPLATE_DIR']

  cwl = args.pop

  file = case cwl
         when /^(.+)#.+$/
           $1
         else
           cwl
         end
  raise "No such file: #{file}" unless File.exist? file

  force = opts.fetch('force', false)
  target_dir = if opts.include? 'target-dir'
                 dir = opts['target-dir']
                 if Dir.exist?(dir) and not force
                   raise "#{dir} already exist"
                 end
                 FileUtils.mkdir_p dir
                 File.expand_path(dir)
               else
                 Dir.mktmpdir
               end
  dst = File.join(target_dir, 'workdir')
  FileUtils.mkdir_p(dst) unless Dir.exist?(dst)

  begin
    nets = cwl2wfnet(cwl, dst)
    nets.each{ |n|
      open(File.join(n[:destination], 'job.yml'), 'w') { |f|
        #f.puts wfnet2entr(n[:net])
        f.puts wfnet2medal(n[:net])
      }
      if opts.include? 'print-dot'
        open(File.join(n[:destination], 'net.dot'), 'w') { |f|
          f.puts n[:net].to_dot
        }
      end
    }

    # TODO fix it
    fluentd_dir = File.join(dst, 'fluentd')
    FileUtils.mkdir fluentd_dir
    FileUtils.cp(File.join(template_dir, 'fluentd.conf'), fluentd_dir)

    FileUtils.cp(File.join(template_dir, 'run.sh'), dst)
  rescue UnsupportedError => e
    FileUtils.remove_entry(dst) if Dir.exist? dst
    warn e
    exit 33
  rescue StandardError, CWLParseError, CWLInspectionError => e
    FileUtils.remove_entry(dst) if Dir.exist? dst
    raise e
  end
  puts target_dir
end

if $0 == __FILE__
  ep3_init(ARGV)
end
