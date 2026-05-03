defmodule DurableServer.SourcePolicyTest do
  use ExUnit.Case, async: true

  @excluded_path "test/durable_server/source_policy_test.exs"

  test "repo-owned code does not use pattern engine APIs" do
    assert_no_token_hits(pattern_engine_tokens(), code_files())
  end

  test "runtime source does not create atoms from runtime strings" do
    assert_no_token_hits(atom_conversion_tokens(), code_files())
    assert_no_quoted_atom_interpolation(runtime_files())
  end

  defp assert_no_token_hits(tokens, files) do
    hits =
      for file <- files,
          token <- tokens,
          content = File.read!(file),
          String.contains?(content, token) do
        {file, token}
      end

    assert hits == []
  end

  defp assert_no_quoted_atom_interpolation(files) do
    hits =
      for file <- files,
          content = File.read!(file),
          quoted_atom_interpolation?(content) do
        file
      end

    assert hits == []
  end

  defp code_files do
    tracked_files()
    |> Enum.filter(&code_file?/1)
    |> Enum.reject(&(&1 == @excluded_path))
  end

  defp runtime_files do
    tracked_files()
    |> Enum.filter(&(String.starts_with?(&1, "lib/") and String.ends_with?(&1, [".ex", ".exs"])))
  end

  defp tracked_files do
    {out, 0} = System.cmd("git", ["ls-files"], cd: File.cwd!())
    String.split(out, "\n", trim: true)
  end

  defp code_file?(path) do
    String.ends_with?(path, [".ex", ".exs"]) or path in ["mix.exs", ".formatter.exs"]
  end

  defp pattern_engine_tokens do
    [
      "Reg" <> "ex",
      "~" <> "r",
      ":r" <> "e.",
      "String.mat" <> "ch",
      "Reg" <> "Exp",
      "reg" <> "exp",
      "re.comp" <> "ile",
      "re.sear" <> "ch",
      "re.mat" <> "ch",
      "re.full" <> "match",
      "re.s" <> "ub",
      "re.spl" <> "it",
      "re.find" <> "all",
      "re.find" <> "iter",
      "from r" <> "e import",
      "import r" <> "e"
    ]
  end

  defp atom_conversion_tokens do
    [
      "String.to_" <> "atom",
      "String.to_existing_" <> "atom",
      "binary_to_" <> "atom",
      "binary_to_existing_" <> "atom",
      "list_to_" <> "atom",
      "list_to_existing_" <> "atom"
    ]
  end

  defp quoted_atom_interpolation?(content) do
    quoted_atom_interpolation?(content, false)
  end

  defp quoted_atom_interpolation?(content, found?) do
    case :binary.match(content, ":\"") do
      :nomatch ->
        found?

      {start, 2} ->
        after_marker = binary_part(content, start + 2, byte_size(content) - start - 2)

        case :binary.match(after_marker, "\"") do
          :nomatch ->
            found?

          {finish, 1} ->
            quoted = binary_part(after_marker, 0, finish)

            if String.contains?(quoted, "\#{") do
              true
            else
              remaining_start = start + 2 + finish + 1

              remaining =
                binary_part(content, remaining_start, byte_size(content) - remaining_start)

              quoted_atom_interpolation?(remaining, false)
            end
        end
    end
  end
end
