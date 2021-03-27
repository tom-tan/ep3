class: CommandLineTool
cwlVersion: v1.0
baseCommand: cat
inputs:
  file:
    type: File[]
    inputBinding: {}
outputs:
  output:
    type: stdout
stdout: output
hints:
  - class: DockerRequirement
    dockerPull: alpine
