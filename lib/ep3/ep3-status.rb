#!/usr/bin/env ruby
# coding: utf-8
require 'optparse'
require 'yaml'
require 'json'

def read_job_status(dir, verbose)
  ret = Hash.new

  file = File.join(dir, 'status', 'ExecutionState')
  ret['job status'] = if File.exist? file
                        st = open(file) { |f|
                          f.gets.chomp
                        }
                        case st
                        when 'wip'              then 'running'
                        when 'success'          then 'finished (success)'
                        when 'permanentFalure'  then 'finished (permanentFalure)'
                        when 'temporaryFailure' then 'finished (temporaryFailure)'
                        end
                      else
                        'not started'
                      end

  cwl = YAML.load_file(File.join(dir, 'cwl', 'job.cwl'))
  if verbose and cwl['class'] == 'Workflow'
    ret['steps'] = Hash[cwl['steps'].map{ |obj|
                          step = if obj.instance_of? Hash
                                   obj['id']
                                 else
                                   obj[0]
                                 end
                          h = read_job_status(File.join(dir, 'steps', step),
                                              verbose)
                          [step, h]
                        }]
  end
  ret
end

def ep3_status(args)
  parser = OptionParser.new
  parser.banner = "Usage: ep3 status [options]"
  parser.on('--target-dir=DIR')
  parser.on('--verbose')

  opts = parser.getopts(args)

  unless args.empty?
    puts parser.help
    exit
  end

  verbose = opts.fetch('verbose', false)
  dir = if opts.include? 'target-dir'
          opts['target-dir']
        else
          raise '--target-dir is needed'
        end
  unless Dir.exist? dir
    raise "Directory not found: #{dir}"
  end

  ret = read_job_status(dir, verbose)

  puts JSON.dump(ret)
end

if $0 == __FILE__
  ep3_status(ARGV)
end
