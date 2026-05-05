defmodule DurableServer.MicroStatePolicyTest do
  use ExUnit.Case, async: true

  alias DurableServer.MicroStatePolicy
  alias DurableServer.MicroStatePolicy.Receipt

  test "defines every durable micro-state category with owner and recovery behavior" do
    expected = [
      :scratchpad,
      :signal_ingress_cursor,
      :boundary_lease_view,
      :rate_limit_view,
      :provider_health,
      :target_attach_state,
      :connector_admission_cache,
      :session_handoff_state,
      :trace_accumulator
    ]

    assert MicroStatePolicy.categories() == expected

    for category <- expected do
      policy = Map.fetch!(MicroStatePolicy.ownership_matrix(), category)

      assert policy.owner in [
               :mezzanine,
               :citadel_kernel,
               :durable_server,
               :provider_store,
               :execution_plane,
               :jido_integration,
               :agent_session_manager,
               :AITrace
             ]

      assert policy.placement in [
               :temporal_history,
               :durable_micro_state,
               :durable_server,
               :cloudflare_durable_object,
               :db_table,
               :ets_cache,
               :provider_store
             ]

      assert policy.redaction == :refs_only
    end
  end

  test "emits ref-only recovery receipts and rejects raw material" do
    assert {:ok, %Receipt{} = receipt} =
             MicroStatePolicy.recovery_receipt(:session_handoff_state, refs())

    assert receipt.owner == :agent_session_manager
    assert receipt.placement == :temporal_history
    assert receipt.replay == :dedupe_handoff_idempotency_key
    assert receipt.redacted?
    refute inspect(receipt) =~ "raw-token"

    assert {:error, {:forbidden_micro_state_material, [:raw_token]}} =
             MicroStatePolicy.recovery_receipt(
               :session_handoff_state,
               Map.put(refs(), :raw_token, "raw-token")
             )
  end

  test "restart recovery rejects stale reads for strict categories" do
    assert {:ok, receipt} =
             MicroStatePolicy.recovery_receipt(:boundary_lease_view, refs())

    assert {:error, {:stale_read_rejected, :boundary_lease_view}} =
             MicroStatePolicy.validate_stale_read(receipt, :stale)

    assert :ok = MicroStatePolicy.validate_stale_read(receipt, :fresh)
  end

  test "bounded stale categories keep explicit policy and still redact" do
    assert {:ok, receipt} =
             MicroStatePolicy.recovery_receipt("provider_health", refs())

    assert receipt.stale_read == :bounded_stale_allowed
    assert receipt.recovery == :refresh_from_provider_health_ref
    assert :ok = MicroStatePolicy.validate_stale_read(receipt, :stale)
  end

  test "unknown micro-state categories are rejected without atom creation" do
    assert {:error, {:unknown_micro_state_category, "unknown_micro_state"}} =
             MicroStatePolicy.classify("unknown_micro_state")

    assert {:error, {:unknown_micro_state_category, :unknown_micro_state}} =
             MicroStatePolicy.classify(:unknown_micro_state)
  end

  test "unknown recovery cursor and lease-view categories fail closed" do
    assert {:error, {:unknown_micro_state_category, "recovery_state_unknown"}} =
             MicroStatePolicy.recovery_receipt("recovery_state_unknown", refs())

    assert {:error, {:unknown_micro_state_category, "cursor_state_unknown"}} =
             MicroStatePolicy.recovery_receipt("cursor_state_unknown", refs())

    assert {:error, {:unknown_micro_state_category, "boundary_lease_unknown"}} =
             MicroStatePolicy.recovery_receipt("boundary_lease_unknown", refs())
  end

  test "stale-read freshness values fail closed" do
    assert {:ok, receipt} =
             MicroStatePolicy.recovery_receipt(:boundary_lease_view, refs())

    assert {:error, {:unknown_stale_read_freshness, :expired}} =
             MicroStatePolicy.validate_stale_read(receipt, :expired)
  end

  defp refs do
    %{
      state_ref: "micro-state://tenant-1/session/1",
      tenant_ref: "tenant://tenant-1",
      trace_ref: "trace://tenant-1/restart/1"
    }
  end
end
