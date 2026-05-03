defmodule DurableServer.UUIDTest do
  use ExUnit.Case, async: true

  alias DurableServer.UUID

  describe "uuid4/0" do
    test "generates a valid UUID v4 string" do
      uuid = UUID.uuid4()

      assert is_binary(uuid)
      assert byte_size(uuid) == 36
      assert valid_uuid4?(uuid)
    end

    test "generates unique UUIDs" do
      uuids = for _ <- 1..100, do: UUID.uuid4()
      assert length(Enum.uniq(uuids)) == 100
    end

    test "version nibble is always 4" do
      for _ <- 1..10 do
        uuid = UUID.uuid4()
        # Version is the 13th character (after 8-4-)
        assert String.at(uuid, 14) == "4"
      end
    end

    test "variant bits are correct (8, 9, a, or b)" do
      for _ <- 1..10 do
        uuid = UUID.uuid4()
        # Variant is the 17th character (after 8-4-4-)
        variant_char = String.at(uuid, 19)
        assert variant_char in ["8", "9", "a", "b"]
      end
    end
  end

  defp valid_uuid4?(uuid) do
    with <<part1::binary-size(8), ?-, part2::binary-size(4), ?-, part3::binary-size(4), ?-,
           part4::binary-size(4), ?-, part5::binary-size(12)>> <- uuid,
         true <- hex?(part1),
         true <- hex?(part2),
         <<"4", tail3::binary>> <- part3,
         true <- hex?(tail3),
         <<variant, tail4::binary>> <- part4,
         true <- variant in [?8, ?9, ?a, ?b],
         true <- hex?(tail4),
         true <- hex?(part5) do
      true
    else
      _ -> false
    end
  end

  defp hex?(part), do: part |> String.to_charlist() |> Enum.all?(&(&1 in ?0..?9 or &1 in ?a..?f))
end
