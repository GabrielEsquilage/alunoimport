import Config

config :alunoimport, Alunoimport.Repo,
  database: System.get_env("DATABASE_NAME"),
  username: System.get_env("DATABASE_USER"),
  password: System.get_env("DATABASE_PASSWORD"),
  hostname: System.get_env("DATABASE_HOST"),
  port: String.to_integer(System.get_env("DATABASE_PORT") || "5432"),
  pool_size: 10,
  show_sensitive_data_on_connection_error: true
