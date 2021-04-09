#!/usr/bin/env ruby
# coding: utf-8
require 'set'

class Place
  attr_reader :variable, :value

  def initialize(var, val = '')
    @variable = var
    @value = val
  end

  def to_s
    if @value.empty?
      "Place(#{@variable})"
    else
      "Place(#{@variable}, #{@value})"
    end
  end

  def to_node
    if @value.empty?
      "#{@variable}"
    else
      "#{@variable}=#{@value}"
    end
  end

  def ==(other)
    other.instance_of?(Place) and
      other.variable == @variable and
      other.value == @value
  end

  def eql?(other)
    self == other
  end

  def hash
    @variable.hash+@value.hash
  end

  def <=>(other)
    if @variable == other.variable
      if @value == '*'
        1
      elsif other.value == '*'
        -1
      else
        @value <=> other.value
      end
    else
      @variable <=> other.variable
    end
  end
end

class Transition
  attr_reader :name, :in, :out, :command

  def initialize(in_:, out:, command: '', name: nil)
    @name = name
    @in = in_.sort
    @out = out.sort
    @command = command
  end

  def to_s
    inp = "[#{@in.map{ |i| i.to_s }.join ', '}]"
    tr = if @command.empty?
           "->"
         else
           "-(#{@command})->"
         end
    out = "[#{@out.map{ |o| o.to_s }.join ', '}]"
    "#{inp} #{tr} #{out}"
  end
end

class IPort
  attr_reader :variable, :value, :port

  def initialize(var, val, port)
    @variable = var
    @value = val
    @port = port
  end
end

class InvocationTransition
  attr_reader :name, :in, :out, :tag, :tmpdir, :workdir, :use

  def initialize(in_:, out:, tag:, tmpdir:, workdir:, use:, name: nil)
    @name = name
    @in = in_
    @use = use
    @out = out
    @tag = tag
    @tmpdir = tmpdir
    @workdir = workdir
  end
end

class PetriNet
  attr_reader :transitions, :possible_places, :tag, :name, :application

  def initialize(name, tag, application)
    @name = name
    @tag = tag
    @application = application
    @transitions = Set.new
    @possible_places = Hash.new
  end

  def <<(tr)
    @transitions << tr
  end

  def to_s
    @transitions.map{ |tr|
      tr.to_s
    }.join "\n"
  end
end

if $0 == __FILE__
end
