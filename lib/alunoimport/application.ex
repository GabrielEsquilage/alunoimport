defmodule Alunoimport.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Alunoimport.Processor,
      Alunoimport.LoggerObserver
    ]

    opts = [strategy: :one_for_one, name: Alunoimport.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
