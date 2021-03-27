class: CommandLineTool
cwlVersion: v1.0
baseCommand: uniq
inputs:
  file:
    type: File
    inputBinding: {}
  count:
    type: boolean?
    inputBinding:
      prefix: -c
outputs:
  output:
    type: stdout
stdout: output
hints:
  - class: DockerRequirement
    dockerPull: alpine
