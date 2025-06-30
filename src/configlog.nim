import yaml, streams, os, options, dotenv, logging
type
    LogConfig* = object
        logPath: string
        keywords: seq[string]
        sysName: string

func getLogPath*(config: LogConfig): string =
    return config.logPath
func getKeywords*(config: LogConfig): seq[string] =
    return config.keywords
func getSysName*(config: LogConfig): string =
    return config.sysName

proc loadConfig*(path: string): Option[seq[LogConfig]] =
    if not fileExists(path):
        return none(seq[LogConfig])
    let s = newFileStream(path)
    var logConfigs: seq[LogConfig]
    try:
        load(s, logConfigs)
    except:
        return none(seq[LogConfig])
    finally:
        s.close()
    return some(logConfigs)

proc loadEnv*(): void =
    let envFile = ".env"
    if fileExists(envFile):
        try:
            dotenv.load()
        except OSError as e:
            logging.error "Error loading environment variables: ", e.msg
    else:
        logging.info "Environment file not found: ", envFile

var webhookUrl: string
proc getWebhookUrl*(): string =
    if webhookUrl.len == 0:
        let envWebhookUrl = getEnv("WEBHOOKURL")
        if envWebhookUrl.len > 0:
            webhookUrl = envWebhookUrl
        else:
            logging.error "WEBHOOKURL environment variable not set."
            quit(1)
    return webhookUrl
