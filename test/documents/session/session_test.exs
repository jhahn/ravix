defmodule Ravix.Documents.SessionTest do
  use ExUnit.Case

  require OK

  alias Ravix.Documents.Session
  alias Ravix.Documents.Store

  setup do
    %{ravix: start_supervised!(Ravix)}
  end

  describe "store/3" do
    test "A document should be stored using the entity id" do
      any_entity = %{id: UUID.uuid4(), cat_name: Faker.Cat.name()}

      {:ok, result} =
        OK.for do
          session_id <- Store.open_session("test")
          stored_document <- Session.store(session_id, any_entity)
          session_state <- Session.fetch_state(session_id)
        after
          [stored_document: stored_document, session_state: session_state]
        end

      documents_in_state = result[:session_state].documents_by_id

      assert result[:stored_document] == any_entity
      assert Map.has_key?(documents_in_state, any_entity.id) == true
    end

    test "A document should be stored using a custom key successfully" do
      any_entity = %{id: UUID.uuid4(), cat_name: Faker.Cat.name()}

      {:ok, result} =
        OK.for do
          session_id <- Store.open_session("test")
          stored_document <- Session.store(session_id, any_entity, "custom_key")
          session_state <- Session.fetch_state(session_id)
        after
          [stored_document: stored_document, session_state: session_state]
        end

      documents_in_state = result[:session_state].documents_by_id

      assert result[:stored_document] == any_entity
      assert Map.has_key?(documents_in_state, "custom_key") == true
    end

    test "If the entity is null, an error should be returned" do
      {:error, :null_entity} =
        OK.for do
          session_id <- Store.open_session("test")
          _ <- Session.store(session_id, nil)
        after
        end
    end

    test "If no valid id is found, an error should be returned" do
      any_entity = %{cat_name: Faker.Cat.name()}

      {:error, :no_valid_id_informed} =
        OK.for do
          session_id <- Store.open_session("test")
          _ <- Session.store(session_id, any_entity)
        after
        end
    end

    test "If an error happens while storing, returns it" do
      any_entity = %{id: UUID.uuid4(), cat_name: Faker.Cat.name()}

      {:error, {:document_already_stored, _stored_entity}} =
        OK.for do
          session_id <- Store.open_session("test")
          _ <- Session.store(session_id, any_entity)

          new_clashing_entity = %{
            id: any_entity.id,
            cat_name: Faker.Cat.name()
          }

          _ <- Session.store(session_id, new_clashing_entity)
        after
        end
    end
  end

  describe "save_changes/1" do
    test "Documents on session should be saved and the session updated" do
      any_entity = %{id: UUID.uuid4(), cat_name: Faker.Cat.name()}

      {:ok, [result, state]} =
        OK.for do
          session_id <- Store.open_session("test")
          _ <- Session.store(session_id, any_entity)
          result <- Session.save_changes(session_id)
          session_state <- Session.fetch_state(session_id)
        after
          [result, session_state]
        end

      assert result["Results"] != []
      assert state.number_of_requests == 1

      first_result = Enum.at(result["Results"], 0)
      {:ok, document_in_session} = Session.State.fetch_document(state, first_result["@id"])

      assert document_in_session.change_vector == first_result["@change-vector"]
    end
  end

  describe "load/1" do
    test "Should load a document to a session successfully" do
      any_entity = %{id: UUID.uuid4(), cat_name: Faker.Cat.name()}

      {:ok, response} =
        OK.for do
          # Create a document and save it
          session_id <- Store.open_session("test")
          _ <- Session.store(session_id, any_entity)
          _ <- Session.save_changes(session_id)
          # Create a new session to fetch the document
          session_id <- Store.open_session("test")
          result <- Session.load(session_id, any_entity.id)
          current_state <- Session.fetch_state(session_id)
        after
          Map.put(result, "state", current_state)
        end

      state = response["state"]
      result = Enum.at(response["Results"], 0)

      assert result["id"] == any_entity.id
      assert result["cat_name"] == any_entity.cat_name
      assert result["@metadata"]["@change-vector"] != nil

      assert state.documents_by_id[any_entity.id].entity ==
               any_entity |> Morphix.stringmorphiform!()
    end

    test "If the document is already in the session, return that it was already loaded" do
      any_entity = %{id: UUID.uuid4(), cat_name: Faker.Cat.name()}

      {:ok, response} =
        OK.for do
          session_id <- Store.open_session("test")
          _ <- Session.store(session_id, any_entity)
          _ <- Session.save_changes(session_id)
          result <- Session.load(session_id, any_entity.id)
          current_state <- Session.fetch_state(session_id)
        after
          Map.put(result, "state", current_state)
        end

      state = response["state"]
      already_loaded = response["already_loaded_ids"]

      assert length(response["Results"]) == 0
      assert map_size(state.documents_by_id) == 1
      assert Enum.any?(already_loaded, fn element -> element == any_entity.id end)
    end
  end
end