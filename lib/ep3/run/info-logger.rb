#!/usr/bin/env ruby
# coding: utf-8
require 'json'
require 'yaml'
require 'msgpack'

def translate_message(obj)
  case obj.fetch('name', '')
  when /^start-execution$/
    if obj['event_type'] == 'start'
      job_name = obj['label'].match(/^ep3\.system\.(.*)\.main$/)[1]
      inputs = open(File.join(*(job_name.split(/\./)[1..-1]+['status', 'inputs.json']))) { |f|
        JSON.load(f)
      }
      cwl = YAML.load_file(File.join(*(job_name.split(/\./)[1..-1]+['cwl', 'job.cwl'])))
      {
        'message' => "#{job_name} started",
        'job' => cwl,
        'inputs' => inputs,
      }
    end
  when 'finish-execution'
    if obj['event_type'] == 'end'
      job_name = obj['label'].match(/^ep3\.system\.(.*)\.main$/)[1]
      status = open(File.join(*(job_name.split(/\./)[1..-1]+['status', 'ExecutionState']))).readlines.first.chomp
      msg = "#{job_name} finished with #{status}"
      if status == 'success'
        out = open(File.join(*(job_name.split(/\./)[1..-1]+['status', 'cwl.output.json']))) { |f|
          JSON.load(f)
        }
        {
          'message' => msg,
          'outputs' => out,
        }
      else
        {
          'message' => msg,
        }
      end
    end
  end
end


if $0 == __FILE__
  begin
    while line = STDIN.gets
      line.chomp!
      json = JSON.parse(line)
      log = translate_message(json)
      if log
        STDOUT.print MessagePack.pack(log)
        STDOUT.flush
      end
    end
  rescue Interrupt
  end
end
