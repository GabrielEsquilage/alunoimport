import Config

# Configure your database
config :alunoimport, Alunoimport.Repo,
  database: "your_database_name",
  username: "your_username",
  password: "your_password",
  hostname: "localhost",
  pool_size: 10
