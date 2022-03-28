defmodule Ravix.Connection.Supervisor do
  use Supervisor

  alias Ravix.Connection
  alias Ravix.Connection.State, as: ConnectionState
  alias Ravix.Connection.RequestExecutor.Supervisor, as: ExecutorSupervisor
  alias Ravix.Documents.Session.Supervisor, as: SessionSupervisor
  alias Ravix.Documents.Conventions

  def start_link(store, otp_app, opts) do
    Supervisor.start_link(__MODULE__, {store, otp_app, opts})
  end

  @spec compile_config(keyword) :: any
  def compile_config(opts) do
    Keyword.fetch!(opts, :otp_app)
  end

  @spec runtime_configs(any(), atom) :: {:error, list} | {:ok, Ravix.Connection.State.t()}
  def runtime_configs(store, otp_app) do
    configs = Application.get_env(otp_app, store)
    conventions = struct(%Conventions{}, configs[:document_conventions])
    configs = struct(%ConnectionState{}, configs)
    configs = put_in(configs.conventions, conventions)

    configs
    |> ConnectionState.validate_configs()
  end

  def init({store, otp_app, _opts}) do
    case runtime_configs(store, otp_app) do
      {:ok, configs} ->
        Supervisor.init(connection_processes(store, configs), strategy: :one_for_one)

      {:error, errors} ->
        raise "Invalid configurations for #{inspect(store)} - #{errors}"
    end
  end

  defp connection_processes(store, configs) do
    [
      %{id: ExecutorSupervisor, start: {ExecutorSupervisor, :start_link, [store]}},
      %{id: Connection, start: {Connection, :start_link, [store, configs]}},
      %{id: SessionSupervisor, start: {SessionSupervisor, :start_link, [store]}}
    ]
  end
end