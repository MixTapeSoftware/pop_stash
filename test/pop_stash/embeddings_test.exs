defmodule PopStash.EmbeddingsTest do
  use ExUnit.Case, async: true

  alias PopStash.Embeddings

  describe "enabled?/0" do
    test "returns false when embeddings are disabled" do
      # In test environment, embeddings are disabled by default
      assert Embeddings.enabled?() == false
    end
  end

  describe "embed/1" do
    test "returns error when embeddings are disabled" do
      assert {:error, :embeddings_disabled} = Embeddings.embed("test text")
    end
  end

  describe "ready?/0" do
    test "returns false when serving is not running" do
      assert Embeddings.ready?() == false
    end
  end
end
