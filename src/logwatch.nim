import asyncdispatch, strutils, os, strformat, json, logging, options, atomics,
        times, tables, sequtils
import configlog, discord, utils

type
    DiscordFormat = object
        sysName: string
        fileName: string
        line: string

type
    WatcherHandle = ref object
        cfg: LogConfig
        stopFlag*: Atomic[bool]
        future*: Future[void]

proc newWatcherHandle*(cfg: LogConfig): WatcherHandle =
    var lock = Atomic[bool]()
    lock.store(false)
    result = WatcherHandle(cfg: cfg, stopFlag: lock,
            future: newFuture[void]())

proc setStopFlag*(handle: WatcherHandle) =
    handle.stopFlag.store(true)

proc getStopFlag*(handle: WatcherHandle): bool =
    return handle.stopFlag.load()

func getJsonContent (sysName: string, fileName: string, line: string): string =
    let discoFormat = DiscordFormat(sysName: sysName, fileName: fileName, line: line)
    let json = %discoFormat
    return json.pretty()

const LOG_SLLEP = 1000 # Sleep time in milliseconds
const CHECK_INTERVAL = 10000 # Interval to check for new log entries in milliseconds
proc watchLog*(handle: WatcherHandle): Future[void] {.async.} =
    logging.info fmt"[{handle.cfg.getSysName()}] Starting log watcher for {handle.cfg.getLogPath()}"
    let logPath = handle.cfg.getLogPath()
    let fileName = extractFilename(logPath)
    let keywords = handle.cfg.getKeywords()
    var lastSize = getFileSizeSafe(logPath).get(0)

    while not handle.getStopFlag():
        if not fileExists(logPath):
            logging.info fmt"Log file {logPath} does not exist."
            await sleepAsync(CHECK_INTERVAL) # Wait before checking again
            continue
        let currentSizeSome = getFileSizeSafe(logPath)
        if currentSizeSome.isNone:
            await sleepAsync(CHECK_INTERVAL) # Wait before checking again
            continue

        let currentSize = currentSizeSome.get()
        if currentSize > lastSize:
            # Log file has been truncated or rotated, reopen it
            let f = open(logPath, fmRead)
            try:
                f.setFilePos(lastSize)
                for line in f.lines:
                    # Check if the line contains any of the keywords
                    for keyword in keywords:
                        if keyword in line:
                            await sendDiscordMessage(getWebhookUrl(),
                            fmt"{getJsonContent(handle.cfg.getSysName(),fileName,line)}")
            except IOError as e:
                logging.error fmt"Error reading log file {logPath}: {e.msg}"
            except OSError as e:
                logging.error fmt"Error reading log file {logPath}: {e.msg}"
            except Exception as e:
                logging.error fmt"Unexpected error: {e.msg}"
            finally:
                f.close()
                lastSize = currentSize
        elif currentSize < lastSize:
            # Log file has been truncated, reset lastSize
            logging.info fmt"Log file {logPath} has been truncated."
            lastSize = 0
        await sleepAsync(LOG_SLLEP) # Wait before checking for new lines

    logging.info fmt"[{handle.cfg.getSysName()}] Stopping log watcher for {logPath}"

var watchers = initTable[string, WatcherHandle]()

proc watchConfig*(configPath: string) {.async.} =
    logging.info fmt"Watching configuration file: {configPath}"
    var lastMod = getLastModificationTime(configPath)
    let config = loadConfig(configPath)
    if config.isNone:
        logging.error "Failed to load configuration."
        return

    while true:
        if not fileExists(configPath):
            logging.info fmt"Config file {configPath} does not exist."
            await sleepAsync(CHECK_INTERVAL) # Wait before checking again
            continue

        let currentMod = getLastModificationTime(configPath)
        if currentMod > lastMod:
            logging.info fmt"Config file {configPath} has been modified."
            lastMod = currentMod
            let newConfigs = loadConfig(configPath)
            if newConfigs.isNone:
                logging.error "Failed to load configuration."
                continue

            for cfg in newConfigs.get():
                let logPath = cfg.getLogPath()
                if not watchers.hasKey(logPath):
                    let handle = newWatcherHandle(cfg)
                    watchers[logPath] = handle
                    handle.future = watchLog(handle)
                    asynccheck handle.future

            var deleteKeys: seq[string] = @[]
            for oldPath, h in watchers.pairs():
                if not newConfigs.get().anyIt(it.getLogPath() == oldPath):
                    logging.info fmt"Removing watcher for {oldPath}"
                    h.setStopFlag()
                    await h.future # Wait for the watcher to finish
                    deleteKeys.add(oldPath)

            for key in deleteKeys:
                watchers.del(key)
        await sleepAsync(CHECK_INTERVAL) # Wait before checking for changes


proc mainLoop*(configPath: string) {.async.} =
    logging.info fmt"Watching configuration file: {configPath}"
    let config = loadConfig(configPath)
    for cfg in config.get():
        let logPath = cfg.getLogPath()
        if not watchers.hasKey(logPath):
            logging.info fmt"Adding watcher for log file: {logPath}"
            let handle = newWatcherHandle(cfg)
            handle.future = watchLog(handle)
            watchers[logPath] = handle

    var futures = toSeq(watchers.values()).mapIt(it.future)
    futures.add(watchConfig(configPath))

    await all(futures)
