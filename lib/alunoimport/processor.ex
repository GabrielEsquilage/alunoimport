defmodule Alunoimport.Processor do
  use GenServer

  alias Alunoimport.Processor

  NimbleCSV.define(MyParser, separator: ",", escape: "\"")

  @registry Alunoimport.Registry
  @endpoint "https://erp-api-stage-52421872894.us-central1.run.app/api-external/v1/matricula/create-student"
  @log_dir "envios_json"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_import(start_line \\ 1) do
    GenServer.cast(__MODULE__, {:start_import, start_line})
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def subscribe do
    Registry.register(@registry, :observers, self())
  end

  @impl true
  def init(:ok) do
    Registry.start_link(keys: :unique, name: @registry)
    File.mkdir_p!(@log_dir)

    initial_state = %{
      status: :idle,
      stats: %{sucesso: 0, erro: 0},
      start_time: nil,
      end_time: nil,
      total_lines: 0
    }

    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:start_import, start_line}, %{status: :running} = state) do
    Registry.dispatch(@registry, :observers, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:already_running})
    end)

    {:noreply, state}
  end

  def handle_cast({:start_import, start_line}, state) do
    processor_pid = self()

    total_lines = "alunos.csv" |> File.stream!() |> Enum.count()

    new_state =
      state
      |> Map.put(:status, :running)
      |> Map.put(:start_time, DateTime.utc_now())
      |> Map.put(:stats, %{sucesso: 0, erro: 0})
      |> Map.put(:total_lines, total_lines)

    Registry.dispatch(@registry, :observers, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:import_started, total_lines})
    end)

    Task.async(fn ->
      "alunos.csv"
      |> File.stream!(read_ahead: 1)
      |> MyParser.parse_stream()
      |> Stream.with_index(1)
      |> Stream.filter(fn {_, index} -> index >= start_line end)
      |> Task.async_stream(&Processor.processar_linha(&1, processor_pid),
        max_concurrency: 1,
        timeout: :infinity,
        ordered: false
      )
      |> Stream.run()

      GenServer.cast(processor_pid, :import_finished)
    end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:tally, status, email, index}, state) do
    new_stats =
      case status do
        :ok -> %{state.stats | sucesso: state.stats.sucesso + 1}
        :error -> %{state.stats | erro: state.stats.erro + 1}
      end

    Registry.dispatch(@registry, :observers, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:aluno_processado, status, email, index})
    end)

    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_cast(:import_finished, state) do
    end_time = DateTime.utc_now()
    new_state = Map.merge(state, %{status: :finished, end_time: end_time})

    Registry.dispatch(@registry, :observers, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:import_finalizado, new_state})
    end)

    {:noreply, new_state}
  end

  def processar_linha({row, index}, processor_pid) do
    [_nome, email | _] = row

    [
      nome,
      email,
      telefone,
      cpf,
      logradouro,
      cep,
      bairro,
      numero,
      cidade_id,
      uf_id,
      raca_id,
      genero_id,
      nascimento
    ] = row

    payload = %{
      "pessoa" => %{
        "nome" => nome,
        "email" => email,
        "telefone" => telefone,
        "cpf" => cpf,
        "endereco" => %{
          "logradouro" => logradouro,
          "cep" => cep,
          "bairro" => bairro,
          "numero" => numero,
          "cidadeId" => String.to_integer(cidade_id),
          "ufId" => String.to_integer(uf_id)
        },
        "racaId" => String.to_integer(raca_id),
        "generoId" => String.to_integer(genero_id),
        "nascimento" => nascimento
      },
      "concursoFilialId" => 30254,
      "concursoCurriculoId" => 1769,
      "concursoCurriculoPlanoPagamentoId" => 5308,
      "diaVencimento" => 10,
      "formaPagamentoId" => 1,
      "termoIds" => [3, 5]
    }

    salvar_json(payload, index)
    status = enviar(payload)

    GenServer.cast(processor_pid, {:tally, status, email, index})
  end

  defp salvar_json(payload, index) do
    cpf_limpo = payload["pessoa"]["cpf"] |> String.replace(~r/[^0-9]/, "")
    nome_arquivo = "linha_#{index}_cpf_#{cpf_limpo}.json"
    caminho = Path.join(@log_dir, nome_arquivo)

    File.write!(caminho, Jason.encode!(payload, pretty: true))
  end

  defp enviar(payload) do
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"User-Agent", "Mozilla/5.0 (Fedora)"}
    ]

    case HTTPoison.post(@endpoint, Jason.encode!(payload), headers,
           recv_timeout: 60_000,
           hackney: [retry: 0]
         ) do
      {:ok, %{status_code: 201}} ->
        File.write!("sucessos.log", "#{payload["pessoa"]["email"]}\n", [:append])
        :ok

      {:ok, %{status_code: 200}} ->
        File.write!("sucessos.log", "#{payload["pessoa"]["email"]}\n", [:append])
        :ok

      {:ok, %{status_code: 400, body: resp_body}} ->
        File.write!("erros_400.log", "#{payload["pessoa"]["email"]} -> #{resp_body}\n", [:append])
        :error

      {:ok, %{status_code: code, body: body}} ->
        :error

      {:error, %{reason: reason}} ->
        :error
    end
  end
end
