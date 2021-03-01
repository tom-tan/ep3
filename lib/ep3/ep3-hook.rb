#!/usr/bin/env ruby
require 'optparse'
require 'fileutils'

def ep3_hook(args)
    extensions = []

    parser = OptionParser.new
    parser.banner = "Usage: ep3 list [options]"
    parser.on('--target-dir=DIR')
    parser.on('--extensions=EXTS') { |exts|
        extensions = exts.split(',')
    }
  
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

    unless ENV.include? 'EP3_EXT_PATH'
        raise 'EP3_EXT_PATH is necessary to apply extensions'
    end
    extPaths = ENV['EP3_EXT_PATH'].split(':')

    extFiles = extensions.map{ |e|
        ret = extPaths.find{ |path|
            File.exist?(File.join(path, e))
        }
        if ret.nil?
            raise "Extension #{e} not found"
        end
        File.join(ret, e, 'extension.yml')
    }
    extArgs = extFiles.map{ |e| "--hook=#{e}" }
    apply(File.join(dir, 'workdir', 'job.yml'), extArgs)
end

def apply(network, exts)
    orig = "#{network}.orig"
    unless File.exist?(orig)
        FileUtils.mv(network, orig)
    end
    ret = system("medal-hook #{orig} #{exts.join(' ')} > #{network}")
    ret = 0
    return 1 unless ret
    stepdir = File.join(File.dirname(network), 'steps')
    if Dir.exist?(stepdir)
        Dir.glob("#{stepdir}/*") { |d|
            r = apply(File.join(d, 'job.yml'), exts)
            ret = (ret and r)
        }
    end
    ret
end

if $0 == __FILE__
  ep3_hook(ARGV)
end
