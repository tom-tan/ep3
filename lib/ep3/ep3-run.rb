#!/usr/bin/env ruby
# coding: utf-8
require 'optparse'

Quiet = 0
Normal = 1
Verbose = 2
VeryVerbose = 3

def ep3_run(args)
  loglevel = Normal

  parser = OptionParser.new
  parser.banner = "Usage: ep3 run [options] [<inputs.yml or inputs.json>]"
  parser.on('--target-dir=DIR')
  parser.on('--quiet', 'disable information output') {
    loglevel = Quiet
  }
  parser.on('--verbose', 'verbose output') {
    loglevel = Verbose
  }
  parser.on('--veryverbose', 'more verbose output') {
    loglevel = VeryVerbose
  }

  opts = parser.getopts(args)
  unless args.length <= 1
    puts parser.help
    exit
  end

  unless ENV.include? 'EP3_TEMPLATE_DIR'
    raise 'EP3_TEMPLATE_DIR is necessary'
  end
  template_dir = ENV['EP3_TEMPLATE_DIR']

  unless ENV.include? 'EP3_LIBPATH'
    raise 'EP3_LIBPATH is necessary'
  end

  input = if args.empty?
            File.join(template_dir, 'empty.json')
          else
            f = args.pop
            raise "No such file: #{f}" unless File.exist? f
            f
          end

  dir = if opts.include? 'target-dir'
          opts['target-dir']
        else
          raise '--target-dir is needed'
        end
  unless Dir.exist? dir
    raise "Directory not found: #{dir}"
  end

  open(File.join(dir, 'workdir', 'init.yml'), 'w') { |f|
    f.puts <<EOS
input.yml: #{File.expand_path(input)}
EOS
  }

  lopt = case loglevel
         when Quiet       then '--sys-silent --app-quiet'
         when Normal      then '--sys-silent'
         when Verbose     then '--app-verbose'
         when VeryVerbose then '--verbose'
         end

  env = {
    'EP3_LIBPATH' => ENV['EP3_LIBPATH'],
    'EP3_BINPATH' => ENV['EP3_BINPATH'],
    'EP3_PID' => Process.pid.to_s,
  }
  if ENV.include? 'DOCKER_HOST'
    env['DOCKER_HOST'] = ENV['DOCKER_HOST']
  elsif File.exist?('/var/run/docker.sock')
    env['DOCKER_HOST'] = 'unix:///var/run/docker.sock'
  end

  IO.popen("medal workdir/root.yml -i workdir/init.yml --workdir=workdir --tmpdir=tmpdir --leave-tmpdir #{lopt} --log=/dev/stdout", 'r+',
           :chdir=> dir) { |io|
    open(File.join(dir, 'medal-log.json'), 'w') do |log|
      io.each_line { |l|
        warn l
        log.puts l
      }
    ensure
      rest = io.read
      unless rest.empty?
        warn rest
        log.puts rest
      end
      log.flush
    end
  }
  status = Process.last_status
  if !status.nil? and status.exited?
    status.exitstatus
  else
    1
  end
rescue Interrupt
  # nop
  1
rescue SignalException
  # nop
  1
end

if $0 == __FILE__
  ep3_run(ARGV)
end
