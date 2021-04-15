#!/usr/bin/env ruby
# coding: utf-8
require 'set'

class Place
  attr_reader :variable, :value

  def initialize(var, val = '')
    @variable = var
    @value = val
  end

  def to_h
    {
      'place' => @variable,
      'pattern' => @value,
    }
  end
end

class Transition
  attr_reader :name, :in, :out, :command

  def initialize(in_:, out:, command: '', name: nil, preLog: nil, successLog: nil, failureLog: nil)
    @name = name
    @in = in_
    @out = out
    @command = command
    @preLog = preLog
    @successLog = successLog
    @failureLog = failureLog
  end

  def to_h
    cmd = if @command.nil? or @command.empty?
            'true'
          elsif @command.instance_of? Array
            @command.join("\n")
          else
            @command
          end
    {
      'name' => @name,
      'type' => 'shell',
      'in' => @in.map{ |i| i.to_h },
      'out' => @out.map{ |o| o.to_h },
      'command' => cmd,
      'log' => {
        'pre' => @preLog.to_h,
        'success' => @successLog.to_h,
        'failure' => @failureLog.to_h,  
      }.compact,
    }.compact
  end
end

class IPort
  attr_reader :variable, :value, :port

  def initialize(var, val, port)
    @variable = var
    @value = val
    @port = port
  end

  def to_h
    {
      'place' => @variable,
      'pattern' => @value,
      'port-to' => @port,
    }
  end
end

class InvocationTransition
  attr_reader :name, :in, :out, :tag, :tmpdir, :workdir, :use, :preLog, :successLog, :failureLog

  def initialize(in_:, out:, tag:, tmpdir:, workdir:, use:, name: nil, preLog: nil, successLog: nil, failureLog: nil)
    @name = name
    @in = in_
    @use = use
    @out = out
    @tag = tag
    @tmpdir = tmpdir
    @workdir = workdir
    @preLog = preLog
    @successLog = successLog
    @failureLog = failureLog
  end

  def to_h
    {
      'name' => @name,
      'type' => 'invocation',
      'use' => @use,
      'configuration' => {
        'tag' => @tag,
        'tmpdir' => @tmpdir,
        'workdir' => @workdir,
      }.compact,
      'in' => @in.map{ |i| i.to_h },
      'out' => @out.map{ |o| o.to_h },
      'log' => {
        'pre' => @preLog.to_h,
        'success' => @successLog.to_h,
        'failure' => @failureLog.to_h
      }.compact
    }.compact
  end
end

class LogEntry
  attr_reader :command, :level

  def initialize(command:, level:)
    @command = command
    @level = level
  end

  def to_h
    {
      'command' => @command,
      'level' => @level,
    }
  end
end

class PetriNet
  attr_reader :transitions, :tag, :name, :application
  attr_accessor :preLog, :successLog, :failureLog

  def initialize(name, tag, application)
    @name = name
    @tag = tag
    @application = application
    @transitions = Set.new
  end

  def <<(tr)
    @transitions << tr
  end

  def to_h
    {
      'configuration' => {
        'tag' => @tag,
        'env' => [
          {
            'name' => 'PATH',
            'value' => '$EP3_LIBPATH/runtime:$PATH',
          },
          {
            'name' => 'DOCKER_HOST',
            'value' => '$DOCKER_HOST',
          },
        ],
      },
      'application' => @application,
      'name' => @name,
      'type' => 'network',
      'in' => [
        {
          'place' => 'entrypoint',
          'pattern' => '_',  
        },
      ],
      'out' => [
        {
          'place' => 'cwl.output.json',
          'pattern' => '_',
        },
        {
          'place' => 'ExecutionState',
          'pattern' => '_',
        },
      ],
      'transitions' => @transitions.map{ |t| t.to_h }
    }.compact
  end
end

if $0 == __FILE__
end
