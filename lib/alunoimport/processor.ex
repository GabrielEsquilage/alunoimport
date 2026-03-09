defmodule Alunoimport.Processor do
  @moduledoc """
  Processador central para importação de CSV e atualização de status financeiro.
  """
  use GenServer
  require Logger

  # Removido alias não utilizado para evitar warnings de compilação
  NimbleCSV.define(MyParser, separator: ",", escape: "\"")

  @registry Alunoimport.Registry
  @api_endpoint_external "https://erp-api-stage-52421872894.us-central1.run.app/api-external/v1/matricula/create-student"
  @log_dir "envios_json"
  @concurso_filial_id 25638
  @concurso_curriculo_id 2176
  @concurso_curriculo_plano_pagamento_id 6548

  # --- Interface Pública ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Inicia a importação baseada no arquivo CSV."
  def start_import(start_line \\ 1), do: GenServer.cast(__MODULE__, {:start_import, start_line})

  @doc "Inicia o processamento de alunos já pagos no banco de dados."
  def processar_alunos_pagos, do: GenServer.cast(__MODULE__, :processar_alunos_pagos)

  @doc "Permite que outros processos (como LoggerObserver) se inscrevam para receber eventos."
  def subscribe, do: Registry.register(@registry, :observers, self())

  def get_status, do: GenServer.call(__MODULE__, :get_status)

  # --- Callbacks GenServer ---

  @impl true
  def init(:ok) do
    Registry.start_link(keys: :unique, name: @registry)
    File.mkdir_p!(@log_dir)

    {:ok,
     %{
       status: :idle,
       stats: %{sucesso: 0, erro: 0},
       total_lines: 0
     }}
  end

  @impl true
  def handle_call(:get_status, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast({:start_import, start_line}, state) do
    processor_pid = self()
    arquivo = "alunos.csv"

    if File.exists?(arquivo) do
      total_lines = arquivo |> File.stream!() |> Enum.count()
      Logger.info(">>> CSV detectado: #{total_lines} linhas.")

      Task.start(fn ->
        arquivo
        |> File.stream!(read_ahead: 1)
        |> MyParser.parse_stream()
        |> Stream.with_index(1)
        |> Stream.filter(fn {_, index} -> index >= start_line end)
        |> Enum.each(fn row_data ->
          processar_linha(row_data, processor_pid)
          # Delay de segurança para evitar Rate Limit no envio direto do CSV
          Process.sleep(1000)
        end)

        GenServer.cast(processor_pid, :import_finished)
      end)

      {:noreply, %{state | status: :running, total_lines: total_lines}}
    else
      Logger.error(">>> Erro: Arquivo 'alunos.csv' não encontrado.")
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:processar_alunos_pagos, state) do
    atualizar_status_pagamento_db()
    processor_pid = self()

    Task.start(fn ->
      case autenticar_api() do
        {:ok, access_token} ->
          ids = obter_lista_candidatos_pagos()
          Logger.info(">>> Encontrados #{Enum.count(ids)} candidatos para disparar.")
          processar_disparos_api(ids, access_token, processor_pid)

        {:error, reason} ->
          Logger.error(">>> Falha na autenticação inicial: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:tally, status, _id, _index}, state) do
    new_stats =
      case status do
        :ok -> %{state.stats | sucesso: state.stats.sucesso + 1}
        :error -> %{state.stats | erro: state.stats.erro + 1}
      end

    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_cast(:import_finished, state) do
    Logger.info(">>> Processo concluído com sucesso.")
    {:noreply, %{state | status: :finished}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Funções de Processamento ---

  def processar_linha({row, index}, processor_pid) do
    try do
      [
        nome,
        email,
        telefone,
        cpf,
        logradouro,
        cep,
        bairro,
        numero,
        cidade,
        uf,
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
            "cidade" => cidade,
            "uf" => uf
          },
          "racaId" => String.to_integer(raca_id),
          "generoId" => String.to_integer(genero_id),
          "nascimento" => nascimento
        },
        "concursoFilialId" => @concurso_filial_id,
        "concursoCurriculoId" => @concurso_curriculo_id,
        "concursoCurriculoPlanoPagamentoId" => @concurso_curriculo_plano_pagamento_id,
        "diaVencimento" => 10,
        "formaPagamentoId" => 1,
        "termoIds" => [3, 5]
      }

      salvar_json(payload, index)
      status = enviar_externo(payload)
      GenServer.cast(processor_pid, {:tally, status, email, index})
    rescue
      e ->
        Logger.error(">>> Erro parsing na linha #{index}: #{inspect(e)}")
        GenServer.cast(processor_pid, {:tally, :error, "fail", index})
    end
  end

  defp atualizar_status_pagamento_db do
    query = ~s"""
    UPDATE FIN.financeiro SET status_id = 9
    WHERE candidato_id IN (
        SELECT id FROM aca.candidato
        WHERE concurso_curriculo_id = #{@concurso_curriculo_id}
          AND concurso_curriculo_plano_pagamento_id = #{@concurso_curriculo_plano_pagamento_id}
          AND concurso_filial_id = #{@concurso_filial_id}
    )
    """
    Ecto.Adapters.SQL.query(Alunoimport.Repo, query, [])
  end

  defp obter_lista_candidatos_pagos do
    query = ~s"""
    SELECT encode(can.id::text::bytea, 'base64')
    FROM ACA.candidato can
    INNER JOIN FIN.financeiro fin ON fin.candidato_id = can.id
    LEFT JOIN aca.matricula mat ON can.id = mat.candidato_id
    WHERE fin.status_id = 9 AND mat.id IS NULL
      AND can.concurso_curriculo_id = #{@concurso_curriculo_id}
      AND can.concurso_filial_id = #{@concurso_filial_id}
    """
    {:ok, %{rows: rows}} = Ecto.Adapters.SQL.query(Alunoimport.Repo, query, [])
    List.flatten(rows)
  end

  defp processar_disparos_api(ids, token, pid) do
    Enum.each(ids, fn id ->
      headers = [{"Content-Type", "application/json"}, {"Authorization", "Bearer #{token}"}]
      gcp_key = System.get_env("GCP_API_KEY")

      endpoint =
        "https://erp-api-stage-52421872894.us-central1.run.app/api/v1/queue/matricula/create?api_key=#{gcp_key}"

      payload = Jason.encode!(%{"message" => %{"data" => id}})

      status =
        case HTTPoison.post(endpoint, payload, headers, recv_timeout: 60_000) do
          {:ok, %{status_code: 200}} ->
            :ok

          {:ok, %{status_code: code, body: body}} ->
            Logger.error(">>> Erro API (ID #{id}): #{code} - #{body}")
            :error

          {:error, reason} ->
            Logger.error(">>> Erro conexão: #{inspect(reason)}")
            :error
        end

      GenServer.cast(pid, {:tally, status, "API_QUEUE", id})
      Process.sleep(1000)
    end)
  end

  defp autenticar_api do
      login = System.get_env("API_LOGIN")
      password = System.get_env("API_PASSWORD")

      Logger.debug(">>> [AUTH] Iniciando autenticação...")

      # Ajuste Crítico: Alterado de "senha" para "password" conforme a especificação da API
      body = URI.encode_query(%{"login" => login, "password" => password})
      headers = [{"Content-Type", "application/x-www-form-urlencoded"}]
      url = "https://erp-api-stage-52421872894.us-central1.run.app/api/v1/app/auth/login"

      case HTTPoison.post(url, body, headers, [recv_timeout: 60_000]) do
        {:ok, %{status_code: 200, headers: response_headers}} ->
          Logger.debug(">>> [AUTH] Resposta 200 recebida.")

          # Busca o token nos cabeçalhos de resposta (Response Headers)
          case Enum.find(response_headers, fn {k, _} -> String.downcase(k) == "access_token" end) do
            {_key, access_token} ->
              Logger.info(">>> [AUTH] Sucesso! Access Token obtido.")
              {:ok, access_token}
            _ ->
              Logger.error(">>> [AUTH] Erro: access_token não encontrado nos cabeçalhos: #{inspect(response_headers)}")
              {:error, :token_not_found_in_headers}
          end

        {:ok, %{status_code: code, body: resp_body}} ->
          Logger.error(">>> [AUTH] Falha na autenticação. Status: #{code}, Body: #{resp_body}")
          {:error, {:http_error, code, resp_body}}

        {:error, %{reason: reason}} ->
          Logger.error(">>> [AUTH] Erro de rede: #{inspect(reason)}")
          {:error, reason}
      end
    end

  defp enviar_externo(payload) do
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(@api_endpoint_external, Jason.encode!(payload), headers) do
      {:ok, %{status_code: code}} when code in [200, 201] -> :ok
      _ -> :error
    end
  end

  defp salvar_json(payload, index) do
    cpf = String.replace(payload["pessoa"]["cpf"] || "0", ~r/[^0-9]/, "")
    caminho = Path.join(@log_dir, "linha_#{index}_cpf_#{cpf}.json")
    File.write!(caminho, Jason.encode!(payload, pretty: true))
  end
end
