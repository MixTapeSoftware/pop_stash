defmodule PopStash.Search.TypesenseTest do
  use ExUnit.Case, async: true

  alias PopStash.Search.Typesense

  describe "enabled?/0" do
    test "returns false when typesense is disabled" do
      # In test environment, typesense is disabled by default
      assert Typesense.enabled?() == false
    end
  end

  describe "search_insights/3" do
    test "returns error when embeddings are disabled" do
      assert {:error, :embeddings_disabled} = Typesense.search_insights("project-id", "query")
    end
  end

  describe "search_decisions/3" do
    test "returns error when embeddings are disabled" do
      assert {:error, :embeddings_disabled} = Typesense.search_decisions("project-id", "query")
    end
  end
end
