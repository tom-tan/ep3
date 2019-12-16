class: CommandLineTool
cwlVersion: v1.0
baseCommand: sort
inputs:
  file:
    type: File
    inputBinding: {}
  number:
    type: boolean?
    inputBinding:
      prefix: -n
  reverse:
    type: boolean?
    inputBinding:
      prefix: -r
outputs:
  output:
    type: stdout
stdout: output
hints:
  - class: DockerRequirement
    dockerPull: alpine
