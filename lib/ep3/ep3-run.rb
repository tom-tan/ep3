#!/usr/bin/env ruby
# coding: utf-8
require 'optparse'

def ep3_run(args)
  parser = OptionParser.new
  parser.banner = "Usage: ep3 run [options] [<inputs.yml or inputs.json>]"
  parser.on('--target-dir=DIR')
  parser.on('--debug')
  parser.on('--quiet')

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

  medal_pid = nil
  begin
    open(File.join(dir, 'workdir', 'init.yml'), 'w') { |f|
      f.puts <<EOS
input.yml: #{File.expand_path(input)}
EOS
    }
    logfile = 'medal-log.json'
    debugout = if opts.include?('debug')
                 :err
               else
                 '/dev/null'
               end
    env = {
      'EP3_LIBPATH' => ENV['EP3_LIBPATH'],
      'EP3_PID' => Process.pid.to_s,
    }
    if ENV.include? 'DOCKER_HOST'
      env['DOCKER_HOST'] = ENV['DOCKER_HOST']
    end
    medal_pid = spawn(env,
                      "bash", "-o", "pipefail", "-c", "medal workdir/root.yml -i workdir/init.yml --workdir=workdir --tmpdir=tmpdir --leave-tmpdir --debug 3>&2 2>&1 1>&3 | tee #{logfile}",
                      :chdir => dir, :err => :out, :out => debugout)

    _, status = Process.waitpid2 medal_pid
    medal_pid = nil
    if status.exited?
      status.exitstatus
    else
      1
    end
  rescue Interrupt
    # nop
    1
  ensure
    unless medal_pid.nil?
      Process.kill :TERM, medal_pid
    end
    Process.waitall
  end
end

if $0 == __FILE__
  ep3_run(ARGV)
end
