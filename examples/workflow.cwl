cwlVersion: v1.0
class: Workflow

inputs:
  - id: inp
    type: File

outputs:
  - id: output
    type: File
    outputSource: sort2/output

steps:
  - id: cat
    run: cat.cwl
    in:
      - id: file
        source: inp
    out: [output]
  - id: sort1
    run: sort.cwl
    in:
      - id: file
        source: cat/output
    out: [output]
  - id: uniq
    run: uniq.cwl
    in:
      - id: file
        source: sort1/output
      - id: count
        default: true
    out: [output]
  - id: sort2
    run: sort.cwl
    in:
      - id: file
        source: uniq/output
      - id: number
        default: true
      - id: reverse
        default: true
    out: [output]
