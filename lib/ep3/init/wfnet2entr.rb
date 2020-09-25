#!/usr/bin/env ruby
# coding: utf-8
require_relative 'workflownet'

def to_command(tr)
  cmd = [
    'transition', '-d', '$STATE_DIR', '--tag', '$EP3_TAG',
    *tr.in.map{ |i| ['-i', i.to_node] }.flatten,
    *tr.out.map{ |o| ['-o', o.to_node] }.flatten,
  ].compact
  if tr.name
    cmd = cmd + ['--name', tr.name]
  end
  unless tr.command.empty?
    cmd = cmd + ['--', tr.command]
  end
  cmd.join(' ')
end

def is_already_exclusive(vals)
  if vals.empty?
    true
  elsif vals.first == ''
    is_already_exclusive(vals[1..-1])
  elsif vals.length == 1 and vals.first == '*'
    true
  elsif vals.include?('*')
    false
  else # no wild card
    true
  end
end

def wfnet2entr(net)
  transitions = net.transitions
  trs = transitions.sort_by{ |t| t.in }
  trs = trs.chunk{ |t| t.in.map{|t1| t1.variable } }.map{ |ts| ts[1] }

  watched = transitions.map{ |t| t.in }.flatten.map{ |p| p.variable }.sort.uniq.map{ |v|
    if v.include? '/'
      v
    else
      %Q!$STATE_DIR/#{v}!
    end
  }

  entrs = trs.map{ |ts|
    exclusive = ts.map{ |t| t.in }.transpose.all?{ |p| is_already_exclusive(p.map{ |_| _.value }) }
    if exclusive
      ts.map{ |t|
        inp = t.in.map{ |i|
          v = i.variable
          if v.include? "/"
            v
          else
            %Q!$STATE_DIR/#{v}!
          end
        }.join('\n')
        %Q!printf "#{inp}\\n" | entr -prsn "#{to_command(t)}"&!
      }
    else
      command = ts.chunk{ |t| t.in }.map{ |ch| ch[1] }.map{ |ch|
        cmds = ch.map{ |t| to_command(t) }
        cmds.length == 1 ? cmds.first : '('+cmds.join(' && ')+')'
      }.join(' || ')
      inp = ts.first.in.map{ |i|
        v = i.variable
        if v.include? "/"
          v
        else
          %Q!$STATE_DIR/#{v}!
        end
      }.join('\n')
      %Q!printf "#{inp}\\n" | entr -prsn "#{command}"&!
    end
  }.flatten

  ps = entrs.each_with_index.map { |_, idx|
    "p#{idx}"
  }
  execs = entrs.zip(ps).map { |e, p|
    "#{e}\n#{p}=$!"
  }
  <<EOS
#!/bin/sh

STATE_DIR=status
CWL=cwl/job.cwl
EP3_TAG=#{net.tag}
PATH=#{net.extra_path}:$EP3_LIBPATH/runtime:$PATH
SHELL=/bin/sh
PID=$$
#{net.extra_env.map{|k, v| "#{k}=#{v}" }.join("\n")}

for f in #{watched.join(' ')}
do
  if [ ! -f $f ]; then
    touch $f
  fi
done

#{execs.join("\n")}

trap "kill -s INT #{ps.map{ |p| "$#{p}"}.join(' ')}" USR1

wait
EOS
end

if $0 == __FILE__
end
