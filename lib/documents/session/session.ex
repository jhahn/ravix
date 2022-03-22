defmodule Ravix.Documents.Session do
  use GenServer

  require OK

  alias Ravix.Documents.Session.State, as: SessionState
  alias Ravix.Documents.Session.Manager, as: SessionManager

  def init(session_state) do
    {:ok, session_state}
  end

  @spec start_link(any, SessionState.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_attr, %SessionState{} = initial_state) do
    GenServer.start_link(
      __MODULE__,
      initial_state,
      name: session_id(initial_state.session_id)
    )
  end

  @spec load(binary(), list() | bitstring(), any, keyword() | nil) :: any
  def load(session_id, ids, includes \\ nil, opts \\ nil)
  def load(_session_id, nil, _includes, _opts), do: {:error, :document_ids_not_informed}

  def load(session_id, ids, includes, opts) when is_list(ids) do
    session_id
    |> session_id()
    |> GenServer.call({:load, [document_ids: ids, includes: includes, opts: opts]})
  end

  def load(session_id, id, includes, opts) do
    session_id
    |> session_id()
    |> GenServer.call({:load, [document_ids: [id], includes: includes, opts: opts]})
  end

  @spec delete(binary, map()) :: any
  def delete(session_id, entity) when is_map_key(entity, :id) do
    delete(session_id, entity.id)
  end

  def delete(session_id, id) when is_binary(id) do
    session_id
    |> session_id()
    |> GenServer.call({:delete, id})
  end

  @spec store(binary(), map(), binary() | nil, binary() | nil) :: any
  def store(session_id, entity, key \\ nil, change_vector \\ nil)

  def store(_session_id, entity, _key, _change_vector) when entity == nil,
    do: {:error, :null_entity}

  def store(session_id, entity, key, change_vector) do
    session_id
    |> session_id()
    |> GenServer.call({:store, [entity: entity, key: key, change_vector: change_vector]})
  end

  @spec save_changes(binary) :: any
  def save_changes(session_id) do
    session_id
    |> session_id()
    |> GenServer.call({:save_changes})
  end

  @spec fetch_state(binary()) :: SessionState.t()
  def fetch_state(session_id) do
    session_id
    |> session_id()
    |> :sys.get_state()
  end

  @spec execute_query(any, binary, any) :: any
  def execute_query(query, session_id, method) do
    session_id
    |> session_id()
    |> GenServer.call({:execute_query, query, method})
  end

  @spec session_id(String.t()) :: {:via, Registry, {:sessions, String.t()}}
  defp session_id(id) when id != nil, do: {:via, Registry, {:sessions, id}}

  ####################
  #     Handlers     #
  ####################
  def handle_call(
        {:load, [document_ids: ids, includes: includes, opts: opts]},
        _from,
        %SessionState{} = state
      ) do
    case SessionManager.load_documents(state, ids, includes, opts) do
      {:ok, result} -> {:reply, {:ok, result[:response]}, result[:updated_state]}
      err -> {:reply, err, state}
    end
  end

  def handle_call(
        {:store, [entity: entity, key: key, change_vector: change_vector]},
        _from,
        %SessionState{} = state
      )
      when key != nil do
    OK.try do
      [entity, updated_state] <- SessionManager.store_entity(state, entity, key, change_vector)
    after
      {:reply, {:ok, entity}, updated_state}
    rescue
      err -> {:reply, {:error, err}, state}
    end
  end

  def handle_call(
        {:store, [entity: entity, key: _, change_vector: change_vector]},
        _from,
        %SessionState{} = state
      )
      when entity.id != nil do
    OK.try do
      [entity, updated_state] <-
        SessionManager.store_entity(state, entity, entity.id, change_vector)
    after
      {:reply, {:ok, entity}, updated_state}
    rescue
      err -> {:reply, {:error, err}, state}
    end
  end

  def handle_call(
        {:store, [entity: _, key: _, change_vector: _]},
        _from,
        %SessionState{} = state
      ),
      do: {:reply, {:error, :no_valid_id_informed}, state}

  def handle_call({:save_changes}, _from, %SessionState{} = state) do
    case SessionManager.save_changes(state) do
      {:ok, response} -> {:reply, {:ok, response[:result]}, response[:updated_state]}
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  def handle_call({:delete, id}, _from, %SessionState{} = state) do
    case SessionManager.delete_document(state, id) do
      {:ok, updated_state} -> {:reply, {:ok, id}, updated_state}
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  def handle_call({:execute_query, query, method}, from, %SessionState{} = state) do
    reference = make_ref()
    self_pid = self()

    Task.start(fn ->
      response = SessionManager.execute_query(state, query, method)
      GenServer.cast(self_pid, {:query_processed, reference, response})
    end)

    {:noreply,
     %SessionState{state | running_queries: Map.put(state.running_queries, reference, from)}}
  end

  def handle_cast({:query_processed, reference, response}, %SessionState{} = state) do
    {from, remaining_queries} = Map.pop(state.running_queries, reference)

    GenServer.reply(from, response)

    {:noreply, %SessionState{state | running_queries: remaining_queries}}
  end
end
