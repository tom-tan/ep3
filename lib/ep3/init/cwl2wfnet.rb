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

def cwl2wfnet(cfile, dst, extra_path)
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
  convert(dst, extra_path)
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

  Dir.mkdir File.join(dst, 'outputs')
  Dir.mkdir File.join(dst, 'status')
  Dir.mkdir File.join(dst, 'cwl')
  FileUtils.mkdir_p File.join(dst, '.ep3', 'system')
  FileUtils.mkdir_p File.join(dst, '.ep3', 'info')
  open(File.join(dst, 'cwl', 'job.cwl'), 'w') { |f|
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
        open(File.join(dst, 'steps', s.id, 'status', 'inputs.json'), 'w') { |f|
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

def convert(dst, extra_path, ids = [])
  cwl = CommonWorkflowLanguage.load_file(File.join(dst, 'cwl', 'job.cwl'), false)
  case walk(cwl, '.class')
  when 'CommandLineTool', 'ExpressionTool'
    [
      {
        destination: File.join(*dst),
        net: cmdnet(cwl, extra_path, ids),
      }
    ]
  when 'Workflow'
    net = {
      destination: File.join(*dst),
      net: wfnet(cwl, extra_path, ids),
    }
    nets = cwl.steps.map{ |s|
      convert(File.join(dst, 'steps', s.id), extra_path, ids+['steps', s.id])
    }.flatten
    [net, *nets]
  end
end

def cmdnet(cwl, extra_path, ids)
  control = File.join('.', *ids.map{|_| '..'}, 'ep3', 'control')
  net = PetriNet.new(['ep3', 'system', 'job', *ids, 'main'].join('.'), extra_path)

  net << Transition.new(in_: [Place.new(control, 'stop')], out: [],
                        command: 'kill -s USR1 $PID', name: 'quit')

  net << Transition.new(in_: [Place.new('inputs.json', '*')], out: [],
                        name: 'start-execution')

  net << Transition.new(in_: [Place.new('inputs.json', '*')], out: [Place.new('Allocation', 'wip')], name: 'to-allocation')

  net << Transition.new(in_: [Place.new('Allocation', 'wip')],
                        out: [Place.new('Allocation.err', 'STDERR'), Place.new('Allocation.return', 'RETURN'), Place.new('Allocation.resource', 'STDOUT')],
                        command: 'allocate $CWL $STATE_DIR/inputs.json',
                        name: 'allocate')
  # net << Transition.new(in_: [Place.new('Allocation', 'wip'), Place.new('reconf.command')], out: [Place.new('Allocation', 'success')], name: 'allocate-fallback')
  net << Transition.new(in_: [Place.new('Allocation', 'success')], out: [Place.new('StageIn', 'wip')], name: 'to-staging-in')
  net << Transition.new(in_: [Place.new('Allocation', 'permanentFailure')], out: [Place.new('ExecutionState', 'permanentFailure')], name: 'permanent-fail-allocation')

  net << Transition.new(in_: [Place.new('Allocation.return', '0')], out: [Place.new('Allocation', 'success')])
  net << Transition.new(in_: [Place.new('Allocation.return', '*')], out: [Place.new('Allocation', 'permanentFailure')])

  net << Transition.new(in_: [Place.new('StageIn', 'wip')],
                        out: [Place.new('StageIn.return', 'RETURN'), Place.new('StageIn.err', 'STDERR'),
                              Place.new('cwl.inputs.json', 'STDOUT')],
                        command: %Q!stage-in.rb --outdir=$STATE_DIR/../outputs $CWL $STATE_DIR/inputs.json!,
                        name: 'stage-in')
  net << Transition.new(in_: [Place.new('StageIn', 'success')], out: [Place.new('CommandGeneration', 'wip')],
                        name: 'to-command-generation')
  net << Transition.new(in_: [Place.new('StageIn', 'permanentFailure')],
                        out: [Place.new('ExecutionState', 'permanentFailure'), Place.new('Deallocation', 'wip')],
                        name: 'permanent-fail-staging-in')

  net << Transition.new(in_: [Place.new('StageIn.return', '0')], out: [Place.new('StageIn', 'success')])
  net << Transition.new(in_: [Place.new('StageIn.return', '*')], out: [Place.new('StageIn', 'permanentFailure')])

  net << Transition.new(in_: [Place.new('CommandGeneration', 'wip'), Place.new('cwl.inputs.json', '*')],
                        out: [Place.new('CommandGeneration.return', 'RETURN'), Place.new('CommandGeneration.command', 'STDOUT'),
                              Place.new('CommandGeneration.err', 'STDERR')],
                        command: %Q!inspector.rb $CWL commandline -i $STATE_DIR/cwl.inputs.json --outdir=$STATE_DIR/../outputs!,
                        name: 'generate-command')
  net << Transition.new(in_: [Place.new('CommandGeneration', 'success')], out: [Place.new('Execution', 'wip')],
                        name: 'to-execution')
  net << Transition.new(in_: [Place.new('CommandGeneration', 'permanentFailure')],
                        out: [Place.new('ExecutionState', 'permanentFailure'), Place.new('Deallocation', 'wip')],
                        name: 'permanent-fail-command-generation')
  net << Transition.new(in_: [Place.new('CommandGeneration.return', '0')], out: [Place.new('CommandGeneration', 'success')])
  net << Transition.new(in_: [Place.new('CommandGeneration.return', '*')], out: [Place.new('CommandGeneration', 'permanentFailure')])

  net << Transition.new(in_: [Place.new('Execution', 'wip'), Place.new('Allocation.resource', '*'), Place.new('CommandGeneration.command', '*')],
                        out: [Place.new('Execution.return', 'RETURN'), Place.new('Execution.stdout', 'STDOUT'), Place.new('Execution.stderr', 'STDERR')],
                        command: %Q!execute --resource=$STATE_DIR/Allocation.resource $STATE_DIR/CommandGeneration.command!,
                        name: 'execute')
  net << Transition.new(in_: [Place.new('Execution', 'success')], out: [Place.new('StageOut', 'wip')],
                        name: 'to-staging-out')
  net << Transition.new(in_: [Place.new('Execution', 'permanentFailure')],
                        out: [Place.new('ExecutionState', 'permanentFailure'), Place.new('Deallocation', 'wip')],
                        name: 'permanent-fail-execution')
  net << Transition.new(in_: [Place.new('Execution', 'temporaryFailure')],
                        out: [Place.new('ExecutionState', 'permanentFailure'), Place.new('Deallocation', 'wip')],
                        name: 'temporary-fail-execution')

  successCodes = case cwl.class_
                 when 'CommandLineTool'
                   cwl.successCodes
                 when 'ExpressionTool'
                   [0]
                 end
  successCodes.each{ |c|
    net << Transition.new(in_: [Place.new('Execution.return', c.to_s)],
                          out: [Place.new('Execution', 'success')])
  }

  temporaryFailCodes = case cwl.class_
                       when 'CommandLineTool'
                         cwl.temporaryFailCodes
                       when 'ExpressionTool'
                         []
                       end
  temporaryFailCodes.each{ |c|
    net << Transition.new(in_: [Place.new('Execution.return', c.to_s)], out: [Place.new('Execution', 'temporaryFailure')])
  }

  permanentFailCodes = case cwl.class_
                       when 'CommandLineTool'
                         codes = cwl.permanentFailCodes
                         codes.empty? ? ['*'] : codes
                       when 'ExpressionTool'
                         ['*']
                       end
  permanentFailCodes.each{ |c|
    net << Transition.new(in_: [Place.new('Execution.return', c.to_s)], out: [Place.new('Execution', 'permanentFailure')])
  }

  net << Transition.new(in_: [Place.new('StageOut', 'wip'), Place.new('cwl.inputs.json', '*')],
                        out: [Place.new('cwl.output.json', 'STDOUT'), Place.new('StageOut.err', 'STDERR'), Place.new('StageOut.return', 'RETURN')],
                        command: %Q!inspector.rb $CWL list -i $STATE_DIR/cwl.inputs.json --json --outdir=$STATE_DIR/../outputs!,
                        name: 'stage-out')
  net << Transition.new(in_: [Place.new('StageOut', 'success')],
                        out: [Place.new('ExecutionState', 'success'), Place.new('Deallocation', 'wip')])
  net << Transition.new(in_: [Place.new('StageOut', 'permanentFailure')],
                        out: [Place.new('ExecutionState', 'permanentFailure'), Place.new('Deallocation', 'wip')],
                        name: 'permanent-fail-staging-out')
  net << Transition.new(in_: [Place.new('StageOut', 'temporaryFailure')], out: [Place.new('Deallocation', 'wip')],
                        name: 'temporary-fail-staging-out')
  net << Transition.new(in_: [Place.new('StageOut.return', '0')], out: [Place.new('StageOut', 'success')])
  net << Transition.new(in_: [Place.new('StageOut.return', '*')], out: [Place.new('StageOut', 'permanentFailure')])

#  net << Transition.new(in_: [Place.new('Deallocation', 'wip'), Place.new('deallocate.command')], out: [Place.new('Deallocation', 'success')],
#                        name: 'deallocate-fallback')
  net << Transition.new(in_: [Place.new('Deallocation', 'wip'), Place.new('Allocation.resource', '*')],
                        out: [Place.new('Deallocation.return', 'RETURN'), Place.new('Deallocation.err', 'STDERR')],
                        command: %Q!deallocate $STATE_DIR/Allocation.resource!,
                        name: 'deallocate')
  net << Transition.new(in_: [Place.new('Deallocation.return', '0')], out: [Place.new('Deallocation', 'success')])
  net << Transition.new(in_: [Place.new('Deallocation.return', '*')], out: [Place.new('Deallocation', 'permanentFailure')])

  net << Transition.new(in_: [Place.new('ExecutionState', '*')], out: [],
                        name: 'finish-execution')

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

def wfnet(cwl, extra_path, ids)
  control = File.join('.', *ids.map{|_| '..'}, 'ep3', 'control')
  net = PetriNet.new(['ep3', 'system', 'job', *ids, 'main'].join('.'), extra_path)

  net << Transition.new(in_: [Place.new(control, 'stop')], out: [], command: 'kill -s USR1 $PID')

  net << Transition.new(in_: [Place.new('inputs.json', '*')], out: [],
                        name: 'start-execution')

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
      net << Transition.new(in_: [Place.new('inputs.json', '*')],
                            out: [Place.new("steps/#{s.id}/status/requirement-#{r}", 'STDOUT')],
                            command: "inspector.rb --evaluate-expressions $CWL #{req} -i $STATE_DIR/inputs.json",
                            name: "propagate-req-#{r}")
    }

    cwl.hints.select{ |r|
      not propagated.include?(r.class_) and
        RequirementsForCommandLineTool.include? r.class_
    }.each{ |r|
      net << Transition.new(in_: [Place.new('inputs.json', '*')],
                            out: [Place.new("steps/#{s.id}/status/hint-#{r.class_}", 'STDOUT')],
                            command: "inspector.rb --evaluate-expressions $CWL .hints.#{r.class_} -i $STATE_DIR/inputs.json",
                            name: "propagate-hint-#{r.class_}")
    }

    if s.in.empty?
      net << Transition.new(in_: [Place.new('inputs.json', '*')],
                            out: [Place.new("steps/#{s.id}/status/inputs.json", '{}')],
                            name: "start-#{s.id}")
    end
  }

  cwl.inputs.each{ |inp|
    net << Transition.new(in_: [Place.new('inputs.json', '*')],
                          out: [Place.new(inp.id, 'STDOUT')],
                          command: "jq -c '.#{inp.id}' $STATE_DIR/inputs.json",
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
      [%Q!\\"#{param}\\": #{val.gsub(/"/, '\\"').gsub(/\$/, '\\$')}!, label]
    }.transpose

    unless jqparams.empty?
      inp = ps.flatten.map{ |p| Place.new(p, '*') }
      if inp.empty?
        inp = [Place.new('inputs.json', '*')]
      end
      tr_name = "start-#{step}"
      if ps.empty?
        net << Transition.new(in_: inp,
                              out: [Place.new("steps/#{step}/status/inputs.json", "'{ #{jqparams[0].join(', ') } }'")],
                              name: tr_name)
      else
        net << Transition.new(in_: inp,
                              out: [Place.new("steps/#{step}/status/inputs.json", 'STDOUT')],
                              command: %Q!jq -cs '{ #{jqparams[0].join(', ') } }' #{jqparams[1].flatten.compact.map{ |p| File.join('$STATE_DIR', p) }.join(' ') }!,
                              name: tr_name)
      end
    end

    net << Transition.new(in_: [Place.new("steps/#{step}/status/ExecutionState", 'success')],
                          out: [Place.new("#{step}_ExecutionState", 'success')],
                          name: "notify-#{step}-result")
    s.out.each{ |o|
      net << Transition.new(in_: [Place.new("steps/#{step}/status/ExecutionState", 'success')],
                            out: [Place.new("#{step}_#{o.id}", 'STDOUT')],
                            command: %Q!jq -c '.#{o.id}' steps/#{step}/status/cwl.output.json!)
    }
    net << Transition.new(in_: [Place.new("steps/#{step}/status/ExecutionState", '*')],
                          out: [Place.new("#{step}_ExecutionState", 'STDOUT'), Place.new("ExecutionState", 'STDOUT')],
                          command: "cat steps/#{step}/status/ExecutionState",
                          name: "notify-#{step}-result")
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
    net << Transition.new(in_: [Place.new(sourceLabel, '*')],
                          out: [Place.new(out.id, 'STDOUT')],
                          command: "jq -c . $STATE_DIR/#{sourceLabel}")
  }

  resultPlaces = cwl.steps.map{ |s| Place.new("#{s.id}_ExecutionState", 'success') }

  if cwl.outputs.empty?
    net << Transition.new(in_: resultPlaces,
                          out: [Place.new('cwl.output.json', 'STDOUT'), Place.new('ExecutionState', 'success')],
                          command: "echo {}",
                          name: 'generate-output-object')
  else
    outParams = cwl.outputs.map{ |o| o.id }
    jqparams = outParams.to_enum.with_index.map{ |o, idx|
      [%Q!\\"#{o}\\": .[#{idx}]!, o]
    }.transpose

    net << Transition.new(in_: outParams.map{ |o| Place.new(o, '*') }+resultPlaces,
                          out: [Place.new('cwl.output.json', 'STDOUT'), Place.new('ExecutionState', 'success')],
                          command: %Q!jq -cs '{ #{jqparams[0].join(', ') } }' #{jqparams[1].map{ |j| File.join('$STATE_DIR', j) }.join(' ')}!,
                          name: 'generate-output-object')
  end
  net << Transition.new(in_: [Place.new('ExecutionState', '*')], out: [],
                        name: 'finish-execution')

  net
end

if $0 == __FILE__
end
