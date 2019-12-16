#!/usr/bin/env ruby
# coding: utf-8
require 'fileutils'
require 'json'
require 'yaml'
require 'optparse'
require 'securerandom'
require_relative 'inspector'

def stagein(to_be_skipped, staged_inputs, job, outdir, force_stagein = false)
  Hash[job.each.map{ |k, v|
         if to_be_skipped.call(k, v)
           nil
         elsif staged_inputs.include?(k)
           [k, staged_inputs[k].to_h]
         else
           [k, stagein_(v, outdir, force_stagein).to_h]
         end
       }.compact]
end

def stagein_(obj, outdir, force_stagein = false)
  case obj
  when CWLFile
    if force_stagein or need_staging(obj)
      ret = obj.dup
      name = obj.basename ? obj.basename : SecureRandom.alphanumeric
      ret.path = if obj.path.nil? and obj.contents
                   path = File.join(outdir, name)
                   open(path, 'w') { |f|
                     f.print obj.contents
                   }
                   path
                 else
                   path = File.join(outdir, name)
                   FileUtils.cp(obj.path, path)
                   path
                 end
      ret.location = 'file://'+ret.path
      ret.secondaryFiles = obj.secondaryFiles.map{ |sec|
        stagein_(sec, outdir, true)
      }
      ret.evaluate(nil)
    else
      obj
    end
  when Directory
    if force_stagein or need_staging(obj)
      ret = obj.dup
      name = obj.basename ? obj.basename : SecureRandom.alphanumeric
      ret.path = File.join(outdir, name)
      ret.location = 'file://'+ret.path
      FileUtils.mkdir_p ret.path
      ret.listing = obj.listing.map{ |lst|
        stagein_(lst, ret.path, true)
      }
      ret.evaluate(nil)
    else
      obj
    end
  when CWLRecordValue
    obj.fields.transform_values{ |v|
      stagein_(v, outdir, force_stagein).to_h
    }
  when CWLUnionValue
    stagein_(obj.value, outdir, force_stagein)
  when Array
    obj.map{ |o|
      stagein_(o, outdir, force_stagein).to_h
    }
  else
    obj
  end
end

def need_staging(obj)
  case obj
  when CWLFile
    if obj.path.nil?
      if obj.contents.nil?
        raise CWLInspectionError, 'File literal needs `content` property'
      end
      true
    elsif File.basename(obj.path) == obj.basename
      obj.secondaryFiles.any?{ |sec|
        need_staging(sec)
      }
    else
      true
    end
  when Directory
    if obj.path.nil?
      if obj.listing.empty?
        raise CWLInspectionError, 'Directory literal needs `listing` property'
      end
      true
    elsif File.basename(obj.path) == obj.basename
      obj.listing.any?{ |sec|
        need_staging(sec)
      }
    else
      true
    end
  else
    false
  end
end

def process_init_work_dir(req, cwl, inputs, outdir, runtime)
  staged_inputs = {}
  req.listing.each{ |lst|
    jsreq = get_requirement(cwl, 'InlineJavascriptRequirement')
    case lst
    when CWLFile
      raise UnsupportedError, "Currently File in InitialWorkdirRequirement is not supported."
    when Directory
      raise UnsupportedError, "Currently Directory in InitialWorkdirRequirement is not supported."
    when Dirent
      entry = lst.entry.evaluate(jsreq, inputs, runtime)
      case entry
      when String
        name = if lst.entryname
                 lst.entryname.evaluate(jsreq, inputs, runtime)
               else
                 SecureRandom.alphanumeric
               end
        file = stagein_(CWLFile.load(
                          {
                            'class' => 'File',
                            'basename' => name,
                            'contents' => entry,
                          }, runtime['docdir'], {}, {}),
                        outdir, true)
        unless lst.writable
          mode = File.stat(file.path).mode
          File.chmod(mode & 0111555, file.path)
        end
      when CWLFile
        if lst.entryname
          entry.basename = lst.entryname.evaluate(jsreq, inputs, runtime)
        end
        file = stagein_(entry, outdir, true)
        unless lst.writable
          mode = File.stat(file.path).mode
          File.chmod(mode & 0111555, file.path)
        end
        selected = inputs.select{ |_, v| v == entry }
        unless selected.empty?
          k = selected.keys.first
          staged_inputs[k] = file
        end
      when Directory
        if lst.entryname
          entry.basename = lst.entryname.evaluate(jsreq, inputs, runtime)
        end
        dir = stagein_(entry, outdir, true)
        unless lst.writable
          mode = File.stat(dir.path).mode
          File.chmod(mode & 0111555, dir.path)
        end
        selected = inputs.select{ |_, v| v == entry }
        unless selected.empty?
          k = selected.keys.first
          staged_inputs[k] = dir
        end
      when Dirent
        # ent = Dirent.load(entry, runtime['docdir'], {}, {})
        raise UnsupportedError, "Currently Dirent (evaled) is not supported."
      end
    when Expression
      evaled = lst.evaluate(jsreq, inputs, runtime)
      if evaled.instance_of?(CWLFile) or evaled.instance_of?(Directory)
        stagein_(evaled, outdir, true)
      elsif evaled.instance_of?(Array) and
           evaled.all?{ |e|
              e.instance_of?(CWLFile) or e.instance_of?(Directory)
            }
        evaled.each{ |e|
          stagein_(e, outdir, true)
        }
      else
        raise CWLInspectionError, "Invalid expression #{lst.to_h}: evaluated to #{evaled.class}"
      end
    end
  }
  staged_inputs
end

if $0 == __FILE__
  outdir = nil
  tmpdir = '/tmp'

  opt = OptionParser.new
  opt.banner = "#{$0} [options] <cwl> <job.json>"
  opt.on('--outdir=DIR') { |dir|
    # For InitialWorkDirRequirement
    outdir = File.expand_path dir
  }
  opt.on('--tmpdir=DIR') { |dir|
    tmpdir = File.expand_path dir
  }
  opt.parse!(ARGV)

  unless ARGV.length == 2
    puts opt.help
    exit
  end

  cwlfile, jobfile = ARGV
  unless File.exist? cwlfile
    raise CWLInspectionError, "#{cwlfile} does not exist"
  end
  cwl = CommonWorkflowLanguage.load_file(cwlfile)

  unless File.exist? jobfile
    raise CWLInspectionError, "#{jobfile} does not exist"
  end
  job = if jobfile.end_with? '.json'
          open(jobfile) { |f|
            JSON.load(f)
          }
        else
          YAML.load_file(jobfile)
        end
  docdir = File.dirname(File.expand_path cwlfile)
  inputs = parse_inputs(cwl, job, docdir)
  runtime = eval_runtime(cwlfile, inputs, outdir, tmpdir, docdir)

  req = walk(cwl, '.requirements.InitialWorkDirRequirement', nil)
  staged_inputs = if req
                    process_init_work_dir(req, cwl, inputs, outdir, runtime)
                  else
                    {}
                  end

  to_be_skipped = lambda{ |k, v|
    walk(cwl, ".inputs.#{k}").nil?
  }

  ret = stagein(to_be_skipped, staged_inputs, inputs, outdir)
  puts JSON.dump(ret)
end
