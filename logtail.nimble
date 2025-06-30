# Package

version       = "0.1.0"
author        = "Ipsen87k"
description   = "ログ監視ツール"
license       = "MIT"
srcDir        = "src"
bin           = @["logtail"]


# Dependencies

requires "nim >= 2.2.4"
requires "yaml"
requires "dotenv"