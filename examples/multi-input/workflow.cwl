cwlVersion: v1.0
class: Workflow

requirements:
  - class: MultipleInputFeatureRequirement

inputs:
  - id: file
    type: File
  - id: comment
    type: string

outputs:
  - id: output
    type: File
    outputSource: cat/output

steps:
  - id: echo
    run: echo.cwl
    in:
      - id: message
        source: comment
    out: [output]
  - id: cat
    run: cat.cwl
    in:
      - id: file
        source: [file, echo/output]
    out: [output]
