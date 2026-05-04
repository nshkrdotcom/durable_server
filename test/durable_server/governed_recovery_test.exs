defmodule DurableServer.GovernedRecoveryTest do
  use ExUnit.Case, async: true

  alias DurableServer.GovernedAuthority
  alias DurableServer.Meta
  alias DurableServer.StoredState

  defmodule Counter do
    use DurableServer, vsn: 1

    def dump_state(state), do: state
    def load_state(_old_vsn, state), do: state
  end

  test "stored state recovery accepts ref-only governed authority state" do
    term =
      storage_term(%{
        "credential_ref" => "github/install/123",
        "target_ref" => "repo/openai/example",
        "cursor_authority_ref" => "cursor/page/1",
        "trace" => %{"trace_redaction_ref" => "trace/redacted/1"}
      })

    assert {:ok, %StoredState{state: state}} =
             StoredState.from_storage_term(term, governed_authority: authority())

    assert state["credential_ref"] == "github/install/123"
  end

  test "stored state recovery rejects raw provider authority values" do
    term = storage_term(%{"token" => "env-token"})

    assert {:error, %ArgumentError{} = error} =
             StoredState.from_storage_term(term, governed_authority: authority())

    assert String.contains?(
             Exception.message(error),
             "governed recovery cannot restore raw authority field"
           )
  end

  test "stored state recovery does not reject unrelated authority substrings" do
    term = storage_term(%{"author" => "Ada", "authority_ref" => "authority/durable"})

    assert {:ok, %StoredState{state: state}} =
             StoredState.from_storage_term(term, governed_authority: authority())

    assert state["author"] == "Ada"
  end

  test "object store recovery rejects raw service identity values" do
    term = %{
      "vsn" => 1,
      "state" => %{"service_identity" => "machine-token"},
      "meta" => Meta.encode_to_binary(meta())
    }

    assert {:error, %ArgumentError{} = error} =
             StoredState.from_object_store_term(term, governed_authority: authority())

    assert String.contains?(
             Exception.message(error),
             "governed recovery cannot restore raw authority field"
           )
  end

  test "heartbeat persistence rejects secret-bearing placement env names" do
    assert_raise ArgumentError,
                 "governed heartbeat env var AWS_SECRET_ACCESS_KEY looks authority-bearing; use a non-secret placement key",
                 fn ->
                   GovernedAuthority.validate_heartbeat_env_vars!(authority(), %{
                     "AWS_SECRET_ACCESS_KEY" => "secret"
                   })
                 end
  end

  test "redaction removes configured literal values without pattern engines" do
    authority = authority(redaction_values: ["env-secret", "Bearer runtime-token"])

    assert GovernedAuthority.redact(authority, "token=env-secret auth=Bearer runtime-token") ==
             "token=[REDACTED] auth=[REDACTED]"
  end

  defp storage_term(state) do
    %{
      vsn: 1,
      state: state,
      meta: Meta.to_storage_term(meta())
    }
  end

  defp meta do
    %Meta{
      module: Counter,
      status: :running,
      pid: self(),
      node_str: to_string(Node.self()),
      node_ref: 1,
      last_heartbeat_at: System.system_time(:millisecond),
      crash_history: []
    }
  end

  defp authority(opts \\ []) do
    GovernedAuthority.new!(
      Keyword.merge(
        [
          authority_ref: "authority/durable",
          credential_ref: "credential/ref",
          target_ref: "target/ref",
          service_identity_ref: "identity/ref",
          cursor_authority_ref: "cursor/ref"
        ],
        opts
      )
    )
  end
end
