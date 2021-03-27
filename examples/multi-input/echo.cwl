class: CommandLineTool
cwlVersion: v1.0
baseCommand: echo
inputs:
  message:
    type: string
    inputBinding: {}
outputs:
  output:
    type: stdout
stdout: output
hints:
  - class: DockerRequirement
    dockerPull: alpine
