#!/usr/bin/env ruby
# coding: utf-8
require 'yaml'
require 'fileutils'
require_relative '../runtime/inspector'
require_relative 'workflownet'

RequirementsForCommandLineTool = [
  'InlineJavascriptRequirement', 'SchemaDefRequirement', 'DockerRequirement',
  'SoftwareRequirement', 'InitialWorkDirRequirement', 'EnvVarRequirement',
  'ShellCommandRequirement', 'ResourceRequirement',
]
UnsupportedRequirements = [
  'SoftwareRequirement',
  'ScatterFeatureRequirement', 'StepInputExpressionRequirement',
]

def cwl2wfnet(cfile, dst)
  if cfile.match(/^(.+)(#.+)/)
    basefile = $1
    target = $2
  else
    basefile = cfile
    target = File.basename(cfile)
  end
  basefile = case basefile
             when %r|^file://|, %r|^https?://|
               basefile
             else
               File.expand_path(basefile)
             end
  prepare(basefile, target, dst)
  convert(dst)
end

def prepare(basefile, cfile, dst, exts = {}, dir = [])
  if cfile.instance_of? String
    if cfile.match(/^#(.+)$/)
      cwl = CommonWorkflowLanguage.load_file(basefile+cfile)
    elsif cfile.match(/^(.+)#(.+)$/)
      raise 'Error!'
    else
      cwl = case cfile
            when %r|^.+://|, %r|^/|
              CommonWorkflowLanguage.load_file(cfile)
            else
              CommonWorkflowLanguage.load_file(File.join(File.dirname(basefile), cfile))
            end
    end
  else
    cwl = cfile
  end
  exts = merge_extensions(cwl, exts)
  cwl = replace_extensions(cwl, exts, File.dirname(basefile))

  unsupported = UnsupportedRequirements.select{ |r|
    walk(cwl, ".requirements.#{r}", nil)
  }
  unless unsupported.empty?
    raise UnsupportedError, "Unsupported requirements: #{unsupported.join ', '}"
  end

  unless Dir.exist? dst
    Dir.mkdir dst
  end

  FileUtils.mkdir_p File.join(dst, '.ep3', 'system')
  FileUtils.mkdir_p File.join(dst, '.ep3', 'info')
  open(File.join(dst, 'job.cwl'), 'w') { |f|
    f.puts YAML.dump cwl.to_h
  }

  case walk(cwl, '.class')
  when 'CommandLineTool', 'ExpressionTool'
  when 'Workflow'
    defaults = default_inputs_for_steps(cwl)
    FileUtils.mkdir(File.join(dst, 'steps'))
    cwl.steps.map{ |s|
      stepdir = dir+['steps', s.id]
      FileUtils.mkdir(File.join(dst, 'steps', s.id))
      unsupported_ = UnsupportedRequirements.select{ |r|
        walk(s, ".requirements.#{r}", nil)
      }
      unless unsupported_.empty?
        raise UnsupportedError, "Unsupported requirements: #{unsupported_.join ', '}"
      end
      stepExt = merge_extensions({
                                   'requirements' => s.requirements.to_h
                                 }, exts)
      prepare(basefile, s.run, File.join(dst, 'steps', s.id), stepExt, stepdir)
      if defaults.include? s.id
        open(File.join(dst, 'steps', s.id, 'status', 'input.json'), 'w') { |f|
          f.puts defaults[s.id]
        }
      end
    }
  end
end

def merge_extensions(cwl, exts)
  hash = cwl.to_h
  propagated = RequirementsForCommandLineTool

  precedencedReqs = hash.fetch('requirements', []).map{ |r| r['class'] }
  propedReqs = exts.fetch('requirements', []).map{ |r| r['class'] }.select{ |r|
    propagated.include?(r) and not precedencedReqs.include?(r)
  }
  newReqs = if propedReqs.empty?
              hash.fetch('requirements', [])
            else
              hash.fetch('requirements', [])+propedReqs.map{ |r|
                {
                  'class' => r,
                  '$mixin' => "../status/requirement-#{r}",
                }
              }
            end

  precedencedHints = hash.fetch('hints', []).map{ |h| h['class'] }
  propedHints = exts.fetch('hints', []).map{ |h| h['class'] }.select{ |h|
    propagated.include?(h) and not precedencedHints.include?(h)
  }
  newHints = if propedHints.empty?
               hash.fetch('hints', [])
             else
               hash.fetch('hints', [])+propedHints.map{ |h|
                 {
                   'class' => h,
                   '$mixin' => "../status/hint-#{h}"
                 }
               }
             end
  {
    'requirements' => newReqs,
    'hints' => newHints,
  }
end

def replace_extensions(cwl, exts, basedir)
  hash = cwl.to_h
  hash['requirements'] = exts['requirements']
  hash['hints'] = exts['hints']
  CommonWorkflowLanguage.load(hash, basedir, {}, hash.fetch('$namespaces', nil))
end

def convert(dst, ids = [])
  cwl = CommonWorkflowLanguage.load_file(File.join(dst, 'job.cwl'), false)
  case walk(cwl, '.class')
  when 'CommandLineTool', 'ExpressionTool'
    [
      {
        destination: File.join(*dst),
        net: cmdnet(cwl, ids),
      }
    ]
  when 'Workflow'
    net = {
      destination: File.join(*dst),
      net: wfnet(cwl, ids),
    }
    nets = cwl.steps.map{ |s|
      convert(File.join(dst, 'steps', s.id), ids+['steps', s.id])
    }.flatten
    [net, *nets]
  end
end

def cmdnet(cwl, ids)
  any = '_'
  net = PetriNet.new('command-line-tool', 'ep3.system.main')

  net << Transition.new(in_: [Place.new('entrypoint', any)],
                        out: [Place.new('input.json', "~(entrypoint)"),
                              Place.new('StageIn', 'not-started'), Place.new('CommandGeneration', 'not-started'),
                              Place.new('Execution', 'not-started'), Place.new('StageOut', 'not-started')],
                        name: 'prepare')
  net << Transition.new(in_: [Place.new('StageIn', 'not-started'), Place.new('input.json', any)],
                        out: [Place.new('StageIn', 'success'),
                              Place.new('cwl.input.json', 'STDOUT'), Place.new('StageIn.err', 'STDERR')],
                        command: %q!mkdir -p $MEDAL_TMPDIR/outputs; stage-in.rb --outdir=$MEDAL_TMPDIR/outputs job.cwl ~(input.json)!,
                        name: 'stage-in')

  net << Transition.new(in_: [Place.new('CommandGeneration', 'not-started'), Place.new('StageIn', 'success'),
                              Place.new('cwl.input.json', any)],
                        out: [Place.new('CommandGeneration', 'success'), Place.new('cwl.input.json', '~(cwl.input.json)'),
                              Place.new('CommandGeneration.command', 'STDOUT'),
                              Place.new('CommandGeneration.err', 'STDERR')],
                        command: %Q!inspector.rb job.cwl commandline -i ~(cwl.input.json) --outdir=$MEDAL_TMPDIR/outputs!,
                        name: 'generate-command')

  net << Transition.new(in_: [Place.new('Execution', 'not-started'), Place.new('CommandGeneration', 'success'),
                              Place.new('CommandGeneration.command', any)],
                        out: [Place.new('Execution.return', 'RETURN'), Place.new('Execution.out', 'STDOUT'), Place.new('Execution.err', 'STDERR')],
                        command: %Q!executor ~(CommandGeneration.command)!,
                        name: 'execute')

  successCodes = case cwl.class_
                 when 'CommandLineTool'
                   cwl.successCodes
                 when 'ExpressionTool'
                   [0]
                 end
  successCodes.each{ |c|
    net << Transition.new(in_: [Place.new('Execution.return', c.to_s)],
                          out: [Place.new('Execution', 'success')],
                          name: 'verify-success')
  }

  temporaryFailCodes = case cwl.class_
                       when 'CommandLineTool'
                         cwl.temporaryFailCodes
                       when 'ExpressionTool'
                         []
                       end
  temporaryFailCodes.each{ |c|
    net << Transition.new(in_: [Place.new('Execution.return', c.to_s)],
                          out: [Place.new('Execution', 'temporaryFailure')],
                          name: 'verify-temporaryFailure')
  }
  unless temporaryFailCodes.empty?
    net << Transition.new(in_: [Place.new('Execution', 'temporaryFailure')], out: [],
                          command: '"false"',
                          name: 'fail')
  end

  permanentFailCodes = case cwl.class_
                       when 'CommandLineTool'
                         codes = cwl.permanentFailCodes
                         codes.empty? ? [any] : codes
                       when 'ExpressionTool'
                         [any]
                       end
  permanentFailCodes.each{ |c|
    net << Transition.new(in_: [Place.new('Execution.return', c.to_s)], out: [Place.new('Execution', 'permanentFailure')],
                          name: 'verify-permanentFailure')
  }
  unless permanentFailCodes.empty?
    net << Transition.new(in_: [Place.new('Execution', 'permanentFailure')], out: [],
                          command: '"false"',
                          name: 'fail')
  end

  net << Transition.new(in_: [Place.new('StageOut', 'not-started'), Place.new('Execution', 'success'),
                              Place.new('cwl.input.json', any)],
                        out: [Place.new('StageOut', 'success'), Place.new('ExecutionState', 'success'),
                              Place.new('cwl.output.json', 'STDOUT'), Place.new('StageOut.err', 'STDERR')],
                        command: %Q!inspector.rb job.cwl list -i ~(cwl.input.json) --json --outdir=$MEDAL_TMPDIR/outputs!,
                        name: 'stage-out')
  net
end

def default_inputs_for_steps(cwl)
  ret = {}
  cwl.steps.each{ |s|
    step = s.id
    ps = s.in.map{ |p|
      if p.source.empty? and p.default.nil?
        raise "Warning: #{step}/#{p.id}: in without source nor default is not supported"
      end
      p
    }.select{ |p|
      not p.source.empty?
    }.map{ |param|
      param.source.map{ |s_|
        if s_.match %r|^(.+)/(.+)$|
          "#{$1}_#{$2}"
        else
          s_
        end
      }
    }
    next unless ps.empty?

    i = 0
    jqparams = s.in.map{ |p|
      param = p.id
      src, default = p.source, p.default
      val = if src.empty?
              JSON.dump(default.to_h)
            else
              vals_ = (i...(i+src.length)).map{ |j|
                ".[#{j}]"
              }
              vals = if vals_.length == 1
                       vals_.first
                     elsif p.linkMerge == 'merge_nested'
                       "[#{vals_.join(', ')}]"
                     elsif p.linkMerge == 'merge_flattened'
                       "(#{vals_.join(' + ')})"
                     else
                       raise CWLInspectionError, 'Error'
                     end
              if default.instance_of?(InvalidValue)
                vals
              else
                "(#{vals} // #{JSON.dump(default.to_h)})"
              end
            end
      i = i+src.length unless src.empty?
      %Q!"#{param}": #{val}!
    }

    unless jqparams.empty?
      ret[step] = "{#{jqparams.join(',')}}"
    end
  }
end

def wfnet(cwl, ids)
  any = '_'
  net = PetriNet.new('workflow', 'ep3.system.main')

  cwl.steps.each{ |s|
    propagated = (cwl.requirements.map{ |r| r.class_ } +
                  s.requirements.map{ |r| r.class_ }).sort.uniq.select{ |r|
      RequirementsForCommandLineTool.include? r
    }
    propagated.each{ |r|
      req = if walk(cwl, ".steps.#{s.id}.requirements.#{r}")
              ".steps.#{s.id}.requirements.#{r}"
            else
              ".requirements.#{r}"
            end
      raise "Inheritance of requirements is not implemented!"
      net << Transition.new(in_: [Place.new('entrypoint', any)],
                            out: [Place.new("#{s.id}-requirement-#{r}", 'STDOUT')],
                            command: "inspector.rb --evaluate-expressions job.cwl #{req} -i ~(entrypoint)",
                            name: "propagate-req-#{r}")
    }

    cwl.hints.select{ |r|
      not propagated.include?(r.class_) and
        RequirementsForCommandLineTool.include? r.class_
    }.each{ |r|
      raise "Inheritance of hints is not implemented!"
      net << Transition.new(in_: [Place.new('entrypoint', any)],
                            out: [Place.new("#{s.id}-hint-#{r.class_}", 'STDOUT')],
                            command: "inspector.rb --evaluate-expressions job.cwl .hints.#{r.class_} -i ~(entrypoint)",
                            name: "propagate-hint-#{r.class_}")
    }
  }

  cwl.inputs.each{ |inp|
    net << Transition.new(in_: [Place.new('entrypoint', any)],
                          out: [Place.new(inp.id, 'STDOUT')],
                          command: "jq -c '.#{inp.id}' ~(entrypoint)",
                          name: "parse-#{inp.id}")
  }

  cwl.steps.each{ |s|
    step = s.id
    ps = s.in.map{ |p|
      if p.source.empty? and p.default.nil?
        raise "Warning: #{step}/#{p.id}: in without source nor default is not supported"
      end
      p
    }.select{ |p|
      not p.source.empty?
    }.map{ |param|
      param.source.map{ |s_|
        if s_.match %r|^(.+)/(.+)$|
          "#{$1}_#{$2}"
        else
          s_
        end
      }
    }

    i = 0
    jqparams = s.in.map{ |p|
      param = p.id
      src, default = p.source, p.default
      val = if src.empty?
              JSON.dump(default.to_h)
            else
              vals_ = (i...(i+src.length)).map{ |j|
                ".[#{j}]"
              }
              vals = if vals_.length == 1
                       vals_.first
                     elsif p.linkMerge == 'merge_nested'
                       "[#{vals_.join(', ')}]"
                     elsif p.linkMerge == 'merge_flattened'
                       "(#{vals_.join(' + ')})"
                     else
                       raise CWLInspectionError, 'Error'
                     end
              if default.instance_of?(InvalidValue)
                vals
              else
                "(#{vals} // #{JSON.dump(default.to_h)})"
              end
            end
      label = if src.empty?
                nil
              else
                src.map{ |s_| s_.sub(/\//, '_') }
              end
      i = i+src.length unless src.empty?
      [%Q!"#{param}": #{val}!, label]
    }.transpose

    if jqparams.empty?
      net << Transition.new(in_: [Place.new('entrypoint', any)],
                            out: [Place.new("#{step}-entrypoint", '$EP3_TEMPLATE_DIR/empty.json')],
                            name: "prepare-#{step}")
    else
      inp = ps.flatten.map{ |p| Place.new(p, any) }
      if inp.empty?
        inp = [Place.new('entrypoint', any)]
      end
      tr_name = "prepare-#{step}"
      if ps.empty?
        net << Transition.new(in_: inp,
                              out: [Place.new("#{step}-entrypoint", 'STDOUT')],
                              command: %Q!echo '{ #{jqparams[0].join(', ') } }'!,
                              name: tr_name)
      else
        net << Transition.new(in_: inp,
                              out: [Place.new("#{step}-entrypoint", 'STDOUT')],
                              command: %Q!jq -cs '{ #{jqparams[0].join(', ') } }' #{jqparams[1].flatten.compact.map{ |p| "~(#{p})"}.join(' ') }!,
                              name: tr_name)
      end
    end

    net << InvocationTransition.new(in_: [IPort.new("#{step}-entrypoint", any, 'entrypoint')],
                                    out: [OPort.new('cwl.output.json', "#{step}-cwl.output.json"),
                                          OPort.new('ExecutionState', "#{step}-ExecutionState")],
                                    use: "steps/#{step}/job.yml",
                                    tag: 'ep3.system.main',
                                    tmpdir: "~(tmpdir)/steps/#{step}",
                                    workdir: "~(workdir)/steps/#{step}",
                                    name: "start-#{step}")

    s.out.each{ |o|
      net << Transition.new(in_: [Place.new("#{step}-cwl.output.json", any)],
                            out: [Place.new("#{step}_#{o.id}", 'STDOUT')],
                            command: %Q!jq -c '.#{o.id}' ~(#{step}-cwl.output.json)!,
                            name: "port-#{step}-#{o.id}")
    }
  }

  cwl.outputs.each{ |out|
    unless out.outputSource.length == 1
      raise CWLInspectionError, 'Multiple outputSource is not supported'
    end
    sourceLabel = if out.outputSource.first.match %r|^(.+)/(.+)$|
                    "#{$1}_#{$2}"
                  else
                    out.outputSource.first
                  end
    net << Transition.new(in_: [Place.new(sourceLabel, any)],
                          out: [Place.new(out.id, 'STDOUT')],
                          command: "jq -c . ~(#{sourceLabel})",
                          name: "port-#{sourceLabel}-#{out.id}")
  }

  resultPlaces = cwl.steps.map{ |s| Place.new("#{s.id}-ExecutionState", any) }

  if cwl.outputs.empty?
    net << Transition.new(in_: resultPlaces,
                          out: [Place.new('cwl.output.json', 'STDOUT')],
                          command: "echo {}",
                          name: 'generate-output-object')
  else
    outParams = cwl.outputs.map{ |o| o.id }
    jqparams = outParams.to_enum.with_index.map{ |o, idx|
      [%Q!"#{o}": .[#{idx}]!, o]
    }.transpose

    net << Transition.new(in_: outParams.map{ |o| Place.new(o, any) }+resultPlaces,
                          out: [Place.new('cwl.output.json', 'STDOUT'), Place.new('ExecutionState', 'success')],
                          command: %Q!jq -cs '{ #{jqparams[0].join(', ') } }' #{jqparams[1].map{ |o| "~(#{o})"}.join(' ')}!,
                          name: 'generate-output-object')
  end

  net
end

if $0 == __FILE__
end
