#!/usr/bin/env ruby
# coding: utf-8
require 'optparse'
require_relative 'runtime/inspector'

def detailed_input(input, dir)
  obj = if input.end_with? '.json'
          open(input) { |inp|
            JSON.load(inp)
          }
        else
          YAML.load_file(input)
        end
  dirname = File.dirname input
  cwlfile = File.join(dir, 'workdir', 'job.cwl')
  nss = YAML.load_file(cwlfile).fetch('$namespaces', {})
  Hash[walk(cwlfile, '.inputs', []).select{ |inp|
         obj.fetch(inp.id, nil) or not inp.default.instance_of?(InvalidValue)
       }.map{ |inp|
         val = obj.fetch(inp.id, nil)
         unless inp.default.instance_of?(InvalidValue)
           val = (val or inp.default)
         end
         [inp.id, InputParameter.parse_object(inp.type, val,
                                              dirname, {}, nss).to_h]
       }]
end

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
    open(File.join(dir, 'workdir', 'input.json'), 'w') { |f|
      f.puts JSON.dump detailed_input(input, dir)
    }
    open(File.join(dir, 'workdir', 'init.yml'), 'w') { |f|
      f.puts <<EOS
entrypoint: input.json
EOS
    }
    logfile = 'medal-log.json'
    debugout = if opts.include?('debug')
                 :err
               else
                 '/dev/null'
               end
    medal_pid = spawn({ 'PATH' => "#{ENV['EP3_LIBPATH']}/runtime:#{ENV['PATH']}" },
                      "bash", "-o", "pipefail", "-c", "medal workdir/job.yml -i workdir/init.yml --workdir=workdir --tmpdir=tmpdir --leave-tmpdir --debug 3>&2 2>&1 1>&3 | tee #{logfile}",
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
