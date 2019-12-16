#!/usr/bin/env ruby
# coding: utf-8
require 'json'
require 'msgpack'

def translate_message(obj)
  case obj.fetch('name', '')
  when /^(permanent|temporary)-fail-(.+)$/
    job_name = obj['label'].match(/^ep3\.system\.(.*)\.main$/)[1]
    istep = $1 # intermediate step
    ret = case istep
          when 'permanent' then 'permanentFailure'
          when 'temporary' then 'temporaryFailure'
          else istep
          end
    status = $2.gsub(/-/, ' ')
    ext = if istep == 'execution'
            {
              code: open(File.join(*(job_name.split(/\./)[1..-1]+['status', "Execution.return"]))).readlines.join.to_i,
              command: open(File.join(*(job_name.split(/\./)[1..-1]+['status', "CommandGeneration.command"]))).readlines.join,
            }
          else
            {
              reason: open(File.join(*(job_name.split(/\./)[1..-1]+['status', "#{obj['label']}.err"]))).readlines,
            }
          end
    {
      'message' => "#{status} for #{job_name} finished with #{ret}",
    }.merge(ext)
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
