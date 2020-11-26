#!/usr/bin/env ruby
# coding: utf-8
require 'yaml'
require 'fileutils'
require_relative '../runtime/inspector'
require_relative 'workflownet'

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

def prepare(basefile, cfile, dst)
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

  unsupported = UnsupportedRequirements.select{ |r|
    walk(cwl, ".requirements.#{r}", nil)
  }
  unless unsupported.empty?
    raise UnsupportedError, "Unsupported requirements: #{unsupported.join ', '}"
  end

  unless Dir.exist? dst
    Dir.mkdir dst
  end

  open(File.join(dst, 'job.cwl'), 'w') { |f|
    f.puts YAML.dump cwl.to_h
  }

  case walk(cwl, '.class')
  when 'CommandLineTool', 'ExpressionTool'
  when 'Workflow'
    FileUtils.mkdir(File.join(dst, 'steps'))
    cwl.steps.map{ |s|
      FileUtils.mkdir(File.join(dst, 'steps', s.id))
      unsupported_ = UnsupportedRequirements.select{ |r|
        walk(s, ".requirements.#{r}", nil)
      }
      unless unsupported_.empty?
        raise UnsupportedError, "Unsupported requirements: #{unsupported_.join ', '}"
      end
      prepare(basefile, s.run, File.join(dst, 'steps', s.id))
    }
  end
end

def convert(dst)
  cwl = CommonWorkflowLanguage.load_file(File.join(dst, 'job.cwl'), false)
  case walk(cwl, '.class')
  when 'CommandLineTool', 'ExpressionTool'
    [
      {
        destination: File.join(*dst),
        net: cmdnet(cwl),
      }
    ]
  when 'Workflow'
    net = {
      destination: File.join(*dst),
      net: wfnet(cwl),
    }
    nets = cwl.steps.map{ |s|
      convert(File.join(dst, 'steps', s.id))
    }.flatten
    [net, *nets]
  end
end

def cmdnet(cwl)
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

def wfnet(cwl)
  any = '_'
  net = PetriNet.new('workflow', 'ep3.system.main')

  # prevStep: [nextStep]
  outConnections = Hash.new{ |hash, key| hash[key] = [] }
  # nextStep: [{ prevStep, nextParam, prevParam, index, default }]
  inConnections = Hash.new{ |hash, key| hash[key] = [] }

  cwl.steps.each{ |s|
    step = s.id
    s.in.each{ |p|
      if p.source.empty? and p.default.nil?
        raise "Error: #{step}/#{p.id}: in without source nor default is not supported"
      end
    }
    if s.in.empty?
      outConnections[nil].push step
      inConnections[step].push({
        prevStep: nil,
        nextParam: nil,
        prevParam: nil,
        index: nil,
        default: InvalidValue.new,
      })
    elsif s.in.all?{ |p| p.source.empty? }
      outConnections[nil].push step
      s.in.map{ |p|
        inConnections[step].push({
          prevStep: nil,
          nextParam: p.id,
          prevParam: nil,
          index: nil,
          default: p.default,
        })
      }
    else
      s.in.each{ |p|
        default = p.default
        p.source.each_with_index{ |s_, idx|
          if s_.match %r|^(.+)/(.+)$|
            prev = $1
            prevParam = $2
          else
            prev = nil
            prevParam = s_
          end
          outConnections[prev].push step
          inConnections[step].push({
            prevStep: prev,
            nextParam: p.id,
            prevParam: prevParam,
            index: if p.source.length == 1 then nil else idx end,
            linkMerge: p.linkMerge,
            default: default,
          })
        }
      }
    end
  }

  if cwl.outputs.empty?
    inp = if cwl.steps.empty?
            [Place.new('entrypoint', any)]
          else
            cwl.steps.map{ |s| Place.new("#{s.id}-ExecutionState", 'success') }
          end
    net << Transition.new(in_: inp,
                          out: [Place.new('cwl.output.json', 'STDOUT'), Place.new('ExecutionState', 'success')],
                          command: 'echo {}',
                          name: 'generate-cwl.output.json')
  else
    cwl.outputs.each{ |out|
      out.outputSource.each_with_index{ |o, idx|
        if o.match %r|^(.+)/(.+)$|
          prev = $1
          prevParam = $2
        else
          prev = nil
          prevParam = o
        end
        outConnections[prev].push nil
        inConnections[nil].push({
          prevStep: prev,
          nextParam: out.id,
          prevParam: prevParam,
          index: if out.outputSource.length == 1 then nil else idx end,
          default: InvalidValue.new,
        })
      }
    }
  end

  # outConnections: prevStep: nextStep
  outConnections.each{ |prev, nexts|
    trInp = if prev.nil?
                'entrypoint'
              else
                "#{prev}-cwl.output.json"
              end
    trOut = nexts.map{ |n|
      "#{prev}2#{n}"
    }
    cmds = nil
    reqPlaces = []
    if prev.nil?
      reqPlaces = cwl.steps.map{ |s| Place.new("#{s.id}-requirements", 'FILE') }
      cmds = cwl.steps.map{ |s|
        "inherit-requirements job.cwl #{s.id} ~(entrypoint) > ~(#{s.id}-requirements)"
      }
    end

    net << Transition.new(in_: [Place.new(trInp, any)],
                          out: trOut.map{ |tr| Place.new(tr, "~(#{trInp})") }+reqPlaces,
                          command: cmds,
                          name: "dup-#{trInp}")
  }

  # inConnections: nextStep: { prevStep, nextParam, prevParam, index, default }
  inConnections.each{ |step, arr|
    trOut = if step.nil?
              'cwl.output.json'
            else
              "#{step}-entrypoint"
            end
    trIn = arr.map{ |e| "#{e[:prevStep]}2#{step}" }
    unless step.nil?
      trIn.push "#{step}-requirements"
    end

    multiInputs = Hash.new{ |h, k| h[k] = [] }
    elems = arr.sort_by{ |h| h[:index] }.each_with_index.map{ |hash, idx|
      if hash[:index].nil?
        if hash[:nextParam].nil?
          nil
        elsif hash[:prevParam].nil?
          %Q!#{hash[:nextParam]}: #{JSON.dump(hash[:default].to_h)}!
        elsif hash[:default].instance_of?(InvalidValue)
          %Q!#{hash[:nextParam]}: .[#{idx}].#{hash[:prevParam]}!
        else
          %Q!#{hash[:nextParam]}: (.[#{idx}].#{hash[:prevParam]} // #{JSON.dump(hash[:default].to_h)})!
        end
      else
        if multiInputs.include?(hash[:nextParam])
          multiInputs[hash[:nextParam]][:sources].push ".[#{idx}].#{hash[:prevParam]}"
        else
          multiInputs[hash[:nextParam]] = {
            linkMerge: hash[:linkMerge],
            sources: [".[#{idx}].#{hash[:prevParam]}"]
          }
        end
        nil
      end
    }.compact + multiInputs.map{ |param, vs|
      ss = vs[:sources]
      val = if ss.length == 1
              ss.first
            elsif vs[:linkMerge] == 'merge_nested'
              "[#{ss.join(', ')}]"
            elsif vs[:linkMerge] == 'merge_flattened'
              "(#{vs[:sources].join(' + ')})"
            else
              raise CWLInspectionError, "Unknown linkMerge: #{vs[:linkMerge]}"
            end
      %Q!#{param}: #{val}!
    }

    trInPlaces = trIn.map{ |t| Place.new(t, any) }
    trOutPlaces = [Place.new(trOut, 'STDOUT')]
    if trOut == 'cwl.output.json'
      trInPlaces.push *cwl.steps.map{ |s| Place.new("#{s.id}-ExecutionState", 'success') }
      trOutPlaces.push Place.new('ExecutionState', 'success')
    end

    query = "{ #{elems.join(', ') } }"
    unless step.nil?
      query << "+.[#{trIn.length-1}]"
    end
    cmd = %Q!jq -cs '#{query}' #{trIn.map{ |t| "~(#{t})" }.join(' ')}!

    net << Transition.new(in_: trInPlaces,
                          out: trOutPlaces,
                          command: cmd,
                          name: "generate-#{trOut}")
  }

  cwl.steps.each{ |s|
    step = s.id
    net << InvocationTransition.new(in_: [IPort.new("#{step}-entrypoint", any, 'entrypoint')],
                                    out: [OPort.new('cwl.output.json', "#{step}-cwl.output.json"),
                                          OPort.new('ExecutionState', "#{step}-ExecutionState")],
                                    use: "steps/#{step}/job.yml",
                                    tag: "~(tag).steps.#{step}",
                                    tmpdir: "~(tmpdir)/steps/#{step}",
                                    workdir: "~(workdir)/steps/#{step}",
                                    name: "start-#{step}")
  }
  net
end

if $0 == __FILE__
end
