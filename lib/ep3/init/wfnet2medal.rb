#!/usr/bin/env ruby
require_relative 'workflownet'

def wfnet2medal(net)
    transitions = net.transitions
    tr_entries = transitions.map{ |tr|
        inp = tr.in.map{ |i| 
            %Q|{ place: "#{i.variable}", pattern: "#{i.value}" }|
        }
        out = tr.out.map{ |o|
            %Q|{ place: "#{o.variable}", pattern: "#{o.value}" }|
        }
        <<EOT
  - name: "#{tr.name}"
    type: shell
    in: #{if inp.empty? then [] else ["", *inp].join("\n      - ") end}
    out: #{if out.empty? then [] else ["", *out].join("\n      - ") end}
    command: #{if tr.command.nil? or tr.command.empty? then '"true"' else tr.command end}
EOT
    }
    <<EOS
configurations:
  tag: #{net.tag}
name: #{net.name}
type: network
in:
  - place: entrypoint
    pattern: _
out:
  - place: cwl.output.json
    pattern: _
transitions:
#{tr_entries.join("\n")}
EOS
end
