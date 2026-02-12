defmodule Alunoimport.LoggerObserver do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Alunoimport.Processor.subscribe()
    {:ok, nil}
  end

  @impl true
  def handle_info({:import_started, total_lines}, state) do
    IO.puts(String.duplicate("=", 30))
    IO.puts("Importação iniciada. Total de linhas a processar: #{total_lines}")
    IO.puts(String.duplicate("=", 30))
    {:noreply, state}
  end

  @impl true
  def handle_info({:aluno_processado, :ok, email, index}, state) do
    IO.puts("[OK] Linha #{index}: #{email}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:aluno_processado, :error, email, index}, state) do
    IO.puts("[ERRO] Linha #{index}: #{email}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:import_finalizado, final_state}, state) do
    start_time = final_state.start_time
    end_time = final_state.end_time
    stats = final_state.stats
    tempo_total = DateTime.diff(end_time, start_time, :millisecond) / 1000

    IO.puts(String.duplicate("=", 30))
    IO.puts("Processamento Concluído")
    IO.puts("Tempo Total: #{tempo_total} segundos")
    IO.puts("Sucessos: #{stats.sucesso}")
    IO.puts("Falhas: #{stats.erro}")

    IO.puts(
      "Média: #{if tempo_total > 0, do: Float.round(stats.sucesso / tempo_total, 2), else: 0} req/s"
    )
    IO.puts(String.duplicate("=", 30))
    {:noreply, state}
  end

  @impl true
  def handle_info({:already_running}, state) do
    IO.puts("A importação já está em andamento.")
    {:noreply, state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}
end
