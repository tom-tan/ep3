#!/usr/bin/env ruby
require 'optparse'
require 'fileutils'
require 'json'
require 'time'
require_relative 'runtime/inspector'
require_relative 'runtime/stage-in'

def ep3_list(args)
  parser = OptionParser.new
  parser.banner = "Usage: ep3 list [options]"
  parser.on('--target-dir=DIR')
  parser.on('--copy')
  parser.on('--destination=DST')

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

  dst = if opts.include? 'copy'
          File.expand_path opts.fetch('destination', '.')
        else
          nil
        end
  FileUtils.mkdir_p(dst) if opts.include? 'copy'

  output = open(Dir.glob("#{File.join(dir, 'tmpdir', 'cwl.output.json-*')}").first) { |f|
    JSON.load(f)
  }.transform_values{ |v|
    InputParameter.parse_object(nil, v, File.join(dir, 'outputs'), {}, {})
  }
  to_be_skipped = lambda{ |k, v|
    v.nil?
  }
  puts JSON.dump(stagein(to_be_skipped, {}, output, dst,
                         opts.include?('copy')))
  0
end

if $0 == __FILE__
  ep3_list(ARGV)
end
