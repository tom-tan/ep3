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

class PetriNet
  attr_reader :transitions, :possible_places, :tag, :extra_path, :extra_env

  def initialize(tag, extra_path, extra_env)
    @tag = tag
    @extra_path = extra_path
    @extra_env = extra_env
    @transitions = Set.new
    @possible_places = Hash.new
  end

  def <<(tr)
    @transitions << tr
    tr.in.select{ |p|
      p.value != 'STDOUT' and
        p.value != 'STDERR' and
        p.value != 'RETURN'
    }.each{ |p|
      var = p.variable
      unless @possible_places.include? var
        @possible_places[var] = Set.new
      end
      @possible_places[var] << p
    }
  end

  def to_s
    @transitions.map{ |tr|
      tr.to_s
    }.join "\n"
  end

  def to_dot
    id = 0
    edges = @transitions.map{ |tr|
      dst_set = tr.out.map{ |o|
        label, dests = case o.value
                       when 'STDOUT'
                         ['out', @possible_places.fetch(o.variable, [o])]
                       when 'STDERR'
                         ['err', @possible_places.fetch(o.variable, [o])]
                       when 'RETURN'
                         ['ret', @possible_places.fetch(o.variable, [o])]
                       else
                         if @possible_places.include? o.variable
                           doms = @possible_places[o.variable].map{ |p| p.value }
                           if doms.include?('*') and not doms.include?(o.value)
                             ["=#{o.value}", [Place.new(o.variable, '*')]]
                           else
                             [nil, [o]]
                           end
                         else
                           [nil, [o]]
                         end
                       end
        dests.map{ |d|
          %Q!-> "#{d.to_node}"! +
            (label.nil? ? ';' : %Q! [ label = "#{label}"];!)
        }
      }

      if dst_set.empty?
        ret = [%Q!  "#{id}" [shape = box];!]+tr.in.map{ |i|
          %Q!  "#{i.to_node}" -> "#{id}";!
        }
        id = id.succ
      else
        cmb = dst_set[0].product(*dst_set[1..-1])
        trs = (id...id+cmb.length).to_a
        nodes = trs.map{ |i| [%Q!  "#{i}" [shape = box];!] }
        ret = nodes+trs.zip(cmb).map{ |t, estrs|
          tr.in.map{ |i| %Q!  "#{i.to_node}" -> "#{t}";! } +
            estrs.map{ |s| %Q!  "#{t}" #{s}!}
        }
        id = id+cmb.length
      end
      ret
    }.flatten
    <<DOT
digraph workflow {
#{edges.join("\n")}
}
DOT
  end
end

if $0 == __FILE__
end
