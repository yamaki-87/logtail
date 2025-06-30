import logging, os, strformat, options

func isStringEmpty*(s: string): bool =
    if s == nil:
        return true

    return s.len == 0

proc getFileSizeSafe*(filePath: string): Option[BiggestInt] =
    try:
        return some(getFileSize(filePath))
    except OSError as e:
        logging.error fmt"Error getting file size for {filePath}: {e.msg}"
        return none(BiggestInt)


