import Config

config :alunoimport,
  ecto_repos: [Alunoimport.Repo]

import_config "#{config_env()}.exs"
