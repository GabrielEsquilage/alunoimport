defmodule Alunoimport do
  @moduledoc """
    modulo de cadastro de candidatos em massa
  """
  NimbleCSV.define(MyParser, separator: ",", escape: "\"")

  @endpoint "https://erp-api-dev-922117522963.us-central1.run.app/api-external/v1/aluno-pos/create-student"
  @log_dir "envios_json"

  def disparar do
    File.mkdir_p!(@log_dir)

    IO.puts("Iniciando Disparo de candidatos...")
    inicio = System.monotonic_time(:millisecond)

    result =
      "alunos.csv"
      |> File.stream!(read_ahead: 1)
      |> MyParser.parse_stream()
      |> Stream.with_index(1)
      |> Task.async_stream(fn {row, index} -> processar_linha(row, index) end,
        max_concurrency: 25,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.reduce(%{sucesso: 0, erro: 0}, fn {:ok, status}, acc ->
        case status do
          :ok -> %{acc | sucesso: acc.sucesso + 1}
          :error -> %{acc | erro: acc.erro + 1}
        end
      end)

    fim = System.monotonic_time(:millisecond)
    tempo_total = (fim - inicio) / 1000

    IO.puts(String.duplicate("=", 30))
    IO.puts("Processamento Concluido")
    IO.puts("Tempo Total: #{tempo_total} segundos")
    IO.puts("Sucessos: #{result.sucesso}")
    IO.puts("Falhas: #{result.erro}")

    IO.puts(
      "Média: #{if tempo_total > 0, do: Float.round(result.sucesso / tempo_total, 2), else: 0} req/s"
    )

    IO.puts(String.duplicate("=", 30))
  end

  defp processar_linha(row, index) do
    [_nome, email | _] = row
    IO.puts("📖 Lendo Linha ##{index}: #{email}")

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
      "concursoFilialId" => 14730,
      "concursoCurriculoId" => 1076,
      "concursoCurriculoPlanoPagamentoId" => 3220,
      "diaVencimento" => 10,
      "formaPagamentoId" => 3,
      "termoIds" => [3, 5]
    }

    salvar_json(payload, index)

    enviar(payload)
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
        IO.puts("✨ [201 Created] Sucesso: #{payload["pessoa"]["email"]}")
        File.write!("sucessos.log", "#{payload["pessoa"]["email"]}\n", [:append])
        :ok

      {:ok, %{status_code: 200}} ->
        IO.puts("✅ [200 OK] Criado/Aceito: #{payload["pessoa"]["email"]}")
        File.write!("sucessos.log", "#{payload["pessoa"]["email"]}\n", [:append])
        :ok

      {:ok, %{status_code: 400, body: resp_body}} ->
        IO.puts("❌ Erro 400 (Bad Request): #{payload["pessoa"]["email"]}")
        IO.inspect(resp_body, label: "Detalhes do Erro 400")
        File.write!("erros_400.log", "#{payload["pessoa"]["email"]} -> #{resp_body}\n", [:append])
        :error

      {:ok, %{status_code: code, body: body}} ->
        IO.puts("⚠️ Resposta inesperada: #{code}")
        IO.inspect(body, label: "Corpo da resposta")
        :error

      {:error, %{reason: reason}} ->
        IO.puts("❌ Falha de Rede: #{inspect(reason)}")
        :error
    end
  end
end
