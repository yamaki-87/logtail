import strutils, asyncdispatch, os
import logwatch, configlog, logger

proc main() {.async.} =
  loadEnv()
  initLogger()
  await mainLoop(os.getEnv("CONFIGPATH"))

when isMainModule:
  main().waitFor()
