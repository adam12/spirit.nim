import
  os,
  strscans,
  sequtils,
  posix,
  strutils,
  osproc,
  terminal,
  strtabs

type
  Process = tuple
    name: string
    cmdline: string

var
  pidDest = getCurrentDir() / "tmp/pids"
  logDest = getCurrentDir() / "tmp/logs"
  daemonBin: string

# Cleanup any ANSI attributes at exit
system.addQuitProc(resetAttributes)

if defined(freebsd):
  daemonBin = "/usr/sbin/daemon"
else:
  daemonBin = "/usr/bin/true"

const Usage = """
Usage: spirit COMMAND [opts]

Commands:

  start       [process name]
  stop        [process name]
  restart     [process name]
  log         [process name]
  tail        [process name]
  status

Options:
"""

proc parseProcfile(procfile: string): seq[Process] =
  var
    name, cmdline: string
    p: Process

  result = @[]

  for line in lines procfile:
    if scanf(line, "$w: $+$.", name, cmdline):
      p = (name, cmdline)
      result.add(p)


proc makeLogfile(processName: string): string =
  logDest / processName & ".log"


proc makePid(processName: string): string =
  pidDest / processName & ".pid"


proc makeDaemonPid(processName: string): string =
  pidDest / processName & ".daemon.pid"


proc evalEnv(envFile: string): StringTableRef =
  var key, value: string
  result = newStringTable()

  if not existsFile(envFile): return result

  for line in envFile.lines:
    if scanf(line, "$w=$+$.", key, value):
      result[key] = value


proc lookupPid(pidFile: string): Pid =
  let line = readFile(pidFile)
  parseInt(line.strip)


proc isProcessRunning(pid: Pid): bool =
  return posix.kill(pid, 0) == 0


proc findProcess(processName: string): Process =
  let processes = parseProcfile("./Procfile")
  let matchedProcesses = filter(processes, proc(x: Process): bool = x.name == processName)

  if len(matchedProcesses) == 1:
    result = matchedProcesses[0]
  else:
    quit("Unknown process: " & processName, 1)


proc processStart(processName: string) =
  let pidFile = makeDaemonPid(processName)

  if existsFile(pidFile):
    let pid = lookupPid(pidFile)

    if isProcessRunning(pid):
      return

  let process = findProcess(processName)
  let env = evalEnv(".env")
  for key, value in envPairs():
    env[key] = value

  let args = [
          "-t", processName,
          "-r",
          "-o", makeLogfile(processName),
          "-p", makePid(processName),
          "-P", makeDaemonPid(processName),
          process.cmdline
          ]

  let p = startProcess(
    command=daemonBin,
    args=args,
    env=env,
    options={poStdErrToStdOut, poUsePath}
    )

  close(p)


proc processStop(processName: string) =
  let pidFile = makeDaemonPid(processName)

  if existsFile(pidFile):
    let daemonPid = lookupPid(pidFile)
    discard posix.kill(daemonPid, 15)


proc processLog(processName: string) =
  let logfile = makeLogfile(processName)
  discard execShellCmd("less " & logfile)


proc processTail(processName: string) =
  let logfile = makeLogfile(processname)
  discard execShellCmd("tail -f " & logfile)


proc processStatus(processName: string): string =
  # no daemon pid, no process pid = stopped
  # process pid && running = running
  # else dead

  let daemonPidFile = makeDaemonPid(processName)
  let pidFile = makePid(processName)

  if not existsFile(daemonPidFile) and not existsFile(pidFile):
    result = "stopped"
  elif existsFile(pidFile):
    let pid = lookupPid(pidFile)

    if isProcessrunning(pid):
      result = "running"
    else:
      result = "dead"
  else:
    result = "dead"


proc ensureFoldersExist() =
  createDir(pidDest)
  createDir(logDest)


proc ensureProcfileExists() =
  if not existsFile("./Procfile"):
    quit("Unable to find Procfile", 1)


proc main() =
  ensureFoldersExist()
  ensureProcfileExists()

  if paramCount() == 0: quit(Usage, 1)

  let command = paramStr(1)

  case command
  of "start":
    if paramCount() == 2:
      let processName = paramStr(2)
      processStart(processName)
    else:
      let processes = parseProcfile("./Procfile")
      for process in items processes:
        processStart(process.name)

  of "stop":
    if paramCount() == 2:
      let processName = paramStr(2)
      processStop(processName)
    else:
      let processes = parseProcfile("./Procfile")
      for process in items processes:
        processStop(process.name)

  of "restart":
    if paramCount() == 2:
      let processName = paramStr(2)
      processStop(processName)
      processStart(processName)
    else:
      let processes = parseProcfile("./Procfile")
      for process in items processes:
        processStop(process.name)
        processStart(process.name)

  of "log":
    if paramCount() == 2:
      let processName = paramStr(2)
      processLog(processName)
    else:
      quit(Usage, 1)

  of "tail":
    if paramCount() == 2:
      let processName = paramStr(2)
      processTail(processName)
    else:
      quit(Usage, 1)

  else:
    let processes = parseProcfile("./Procfile")
    for process in items processes:
      echo process.name & ":" & spaces(max(0, 15 - process.name.len)) & processStatus(process.name)


main()

# vim:ts=2:sts=2:sw=2:et
