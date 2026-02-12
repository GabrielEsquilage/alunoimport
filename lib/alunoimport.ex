defmodule Alunoimport do
  @moduledoc """
  Ponto de entrada para o processo de importação de alunos.
  """

  @doc """
  Inicia o processo de importação.

  Delega a chamada para o GenServer `Alunoimport.Processor`
  que gerencia o estado da importação.
  """
  def disparar(start_line \\ 1) do
    Alunoimport.Processor.start_import(start_line)
  end

  @doc """
  Retorna o status atual do processo de importação.
  """
  def status do
    Alunoimport.Processor.get_status()
  end
end
