# Ep3: Extremely Pluggable Pipeline Processor

[![Actions Status](https://badgen.net/github/checks/tom-tan/ep3/master?icon=commonwl)](https://github.com/tom-tan/ep3/actions)
[![license](https://badgen.net/github/license/tom-tan/ep3)](https://github.com/tom-tan/ep3/blob/master/LICENSE)

This is a workflow engine for the [Common Workflow Language](https://www.commonwl.org) which aims to have a pluggable architecture.

## Conformance (CWL v1.0)
### Classes
![CommandLineTool](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/command_line_tool.json?icon=commonwl) ![ExpressionTool](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/expression_tool.json?icon=commonwl) ![Workflow](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/workflow.json?icon=commonwl)

### Required features
![Required](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/required.json?icon=commonwl)

### Requirements (Optional features)
![DockerRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/docker.json?icon=commonwl) ![EnvVarRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/env_var.json?icon=commonwl) ![InitialWorkDirRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/initial_work_dir.json?icon=commonwl) ![InlineJavascriptRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/inline_javascript.json?icon=commonwl) ![MultipleInputFeatureRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/multiple_input.json?icon=commonwl) ![ResourceRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/resource.json?icon=commonwl) ![ScatterFeatureRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/scatter.json?icon=commonwl) ![SchemaDefRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/schema_def.json?icon=commonwl) ![ShellCommandRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/shell_command.json?icon=commonwl) ![StepInputExpressionRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/step_input.json?icon=commonwl) ![SubworkflowFeatureRequirement](https://badgen.net/https/raw.githubusercontent.com/tom-tan/conformance/master/conformance/ep3/cwl_v1.0/ep3_latest/subworkflow.json?icon=commonwl)

## Requirements
- [entr](http://entrproject.org)
- Ruby 2.5.1 or later
- Fluentd 1.3.3 or later
- jq
- nodejs for `InlineJavascriptRequirement`

## How to install
- Install `entr`, `jq`, `ruby`, `nodejs`, and `fluentd`
- Execute the following commands and add `/path/to/ep3` to `$PATH`.
```console
$ git clone --recursive https://github.com/tom-tan/ep3.git
```

## How to test
```console
$ git clone --recursive https://github.com/tom-tan/ep3.git
$ cd ep3
$ cwltest --tool $PWD/ep3-runner --test test.yml
Test [1/1] Workflow example
All tests passed
```

## Example
```console
$ ep3-runner --quiet /path/to/ep3/examples/workflow.cwl /path/to/ep3/examples/inputs.yml | jq .
{
  "output": {
    "class": "File",
    "location": "file:///current/directory/output",
    "path": "/current/directory/output",
    "basename": "output",
    "dirname": "/current/directory",
    "nameroot": "output",
    "nameext": "",
    "checksum": "sha1$c28e458d4e943c743b9b3c46fdab10688a6d68b6",
    "size": 687
  }
}
```

## For developers

### ep3 internals
The `ep3-runner` command consists of the following internal commands:
- `ep3 init`
  - Generates shell scripts that calls `entr`s for the given CWL
- `ep3 run`
  - Executes generated scripts and start processing a workflow
- `ep3 status`
  - Shows the current status of execution
- `ep3 list`
  - Shows the output object for execution result
- `ep3 terminate`
  - Terminates scripts and other processes
- `ep3 resume` (Unimplemented)
- `ep3 stop` (Unimplemented)

### About `checks` badge
The `checks` badge represents the CI result of the latest commit in master branch.

- ![success](https://badgen.net/badge/checks/success/green?icon=commonwl)
  - It passes the basic test. CI also runs the conformance test for this commit. The conformance badges will be available once CI passes the basic test.
- ![failure](https://badgen.net/badge/checks/failure/red?icon=commonwl)
  - It does not pass the basic test. CI skips the conformance test for this commit because it does not work with the most or all the CWL documents.
