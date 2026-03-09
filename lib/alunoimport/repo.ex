defmodule Alunoimport.Repo do
  use Ecto.Repo,
    otp_app: :alunoimport,
    adapter: Ecto.Adapters.Postgres
end
