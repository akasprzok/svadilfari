import Config

config :logger, utc_log: true

import_config "#{config_env()}.exs"
