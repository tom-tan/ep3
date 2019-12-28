# Ep3: Extremely Pluggable Pipeline Processor

This is a CWL engine which aims to have a pluggable architecture.

## Requirements
- [entr](http://entrproject.org)
- Ruby 2.5.1 or later
- Fluentd 1.3.3 or later
- jq
- nodejs
- [cwl-inspector](https://github.com/tom-tan/cwl-inspector)
  - Used as a submodule


## How to install
- Install `entr`, `jq`, `ruby`, and `nodejs`
- Execute the following commands and add `/path/to/ep3` to `$PATH`.
```console
$ git clone --recursive https://github.com/tom-tan/ep3.git
$ gem install -N fluentd
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

## ep3 internals
The `ep3-runner` command consists of the following internal commands:
- `ep3 init`
  - Generate shell scripts that calls `entr`s for the given CWL
- `ep3 run`
  - Execute generated scripts and start processing a workflow
- `ep3 status`
  - Show the current status of execution
- `ep3 list`
  - Show the output object for execution result
- `ep3 terminate`
  - Terminate scripts and other processes
- `ep3 resume` (Unimplemented)
- `ep3 stop` (Unimplemented)
