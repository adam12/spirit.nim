import
  os,
  strscans,
  sequtils,
  posix,
  strutils,
  osproc,
  terminal

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


proc existsPidfile(processName: string): bool =
  return existsFile(makePid processName)


proc lookupPid(processName: string): Pid =
  let pidFile = makePid(processName)
  let line = readFile(pidFile)

  result = parseInt(line.strip)


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
  if existsPidfile(processName):
    let pid = lookupPid(processName)

    if isProcessRunning(pid):
      quit()

  let process = findProcess(processName)
  let args = ["-r", "-o", makeLogfile(processName), "-P", makePid(processName), process.cmdline]

  discard os.execShellCmd(daemonBin & " " & args.join(" "))


proc processStop(processName: string) =
  if existsPidFile(processName):
    let pid = lookupPid(processName)

    if isProcessRunning(pid) and posix.kill(pid, 15) == 0:
      quit(0)


proc processLog(processName: string) =
  let logfile = makeLogfile(processName)
  discard execShellCmd("less " & logfile)


proc processTail(processName: string) =
  let logfile = makeLogfile(processname)
  discard execShellCmd("tail -f " & logfile)


proc processStatus(processName: string): string =
  if existsPidFile(processName):
    let pid = lookupPid(processName)

    if isProcessRunning(pid):
      result = "running"
    else:
      result = "stopped"
  else:
    result = "stopped"


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
