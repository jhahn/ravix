defmodule Ravix.Connection do
  use GenServer

  require OK

  alias Ravix.Connection.State, as: ConnectionState

  def init(network_state) do
    {:ok, network_state}
  end

  @spec start_link(atom(), ConnectionState.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(store, %ConnectionState{} = conn_state) do
    conn_state = put_in(conn_state.store, store)
    conn_state = ConnectionState.Manager.initialize(conn_state)

    GenServer.start_link(__MODULE__, conn_state,
      name: ConnectionState.Manager.connection_id(store)
    )
  end

  @spec fetch_state(atom()) :: {:error, :connection_not_found} | {:ok, ConnectionState.t()}
  def fetch_state(store) do
    try do
      {:ok,
       ConnectionState.Manager.connection_id(store)
       |> :sys.get_state()}
    catch
      :exit, _ -> {:error, :connection_not_found}
    end
  end

  @spec update_topology(atom) :: :ok
  def update_topology(store) do
    store
    |> ConnectionState.Manager.connection_id()
    |> GenServer.cast(:update_topology)
  end

  ####################
  #     Handlers     #
  ####################
  def handle_cast(:update_topology, %ConnectionState{} = state) do
    case ConnectionState.Manager.update_topology(state) do
      {:ok, updated_state} -> {:noreply, updated_state}
      _ -> {:noreply, state}
    end
  end
end