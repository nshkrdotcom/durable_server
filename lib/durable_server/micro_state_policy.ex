defmodule DurableServer.MicroStatePolicy do
  @moduledoc """
  Durable micro-state ownership and recovery policy.

  The policy separates Temporal history from adjacent durable micro-state and
  records how restart, replay, stale-read, eviction, conflict, and redaction
  checks behave for every governed category.
  """

  defmodule Receipt do
    @moduledoc "Ref-only micro-state recovery receipt."

    @enforce_keys [
      :category,
      :owner,
      :placement,
      :state_ref,
      :tenant_ref,
      :trace_ref,
      :recovery,
      :replay,
      :stale_read,
      :eviction,
      :conflict,
      :redaction
    ]
    defstruct [
      :category,
      :owner,
      :placement,
      :state_ref,
      :tenant_ref,
      :trace_ref,
      :recovery,
      :replay,
      :stale_read,
      :eviction,
      :conflict,
      :redaction,
      redacted?: true
    ]

    @type t :: %__MODULE__{
            category: atom(),
            owner: atom(),
            placement: atom(),
            state_ref: String.t(),
            tenant_ref: String.t(),
            trace_ref: String.t(),
            recovery: atom(),
            replay: atom(),
            stale_read: atom(),
            eviction: atom(),
            conflict: atom(),
            redaction: atom(),
            redacted?: true
          }
  end

  @categories [
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
  @category_lookup Map.new(@categories, &{Atom.to_string(&1), &1})

  @policy %{
    scratchpad: %{
      owner: :mezzanine,
      placement: :durable_server,
      recovery: :rebuild_from_temporal_checkpoint,
      replay: :discard_uncommitted_draft,
      stale_read: :reject_stale,
      eviction: :ttl_after_terminal,
      conflict: :last_committed_epoch_wins,
      redaction: :refs_only
    },
    signal_ingress_cursor: %{
      owner: :citadel_kernel,
      placement: :db_table,
      recovery: :resume_from_cursor_ref,
      replay: :dedupe_signal_id,
      stale_read: :reject_stale,
      eviction: :cursor_window,
      conflict: :higher_sequence_wins,
      redaction: :refs_only
    },
    boundary_lease_view: %{
      owner: :citadel_kernel,
      placement: :ets_cache,
      recovery: :rebuild_from_lease_refs,
      replay: :reauthorize_before_materialization,
      stale_read: :reject_stale,
      eviction: :lease_ttl,
      conflict: :fence_epoch_wins,
      redaction: :refs_only
    },
    rate_limit_view: %{
      owner: :durable_server,
      placement: :db_table,
      recovery: :restore_window_counters,
      replay: :idempotent_window_increment,
      stale_read: :bounded_stale_allowed,
      eviction: :window_expiry,
      conflict: :max_counter_wins,
      redaction: :refs_only
    },
    provider_health: %{
      owner: :provider_store,
      placement: :provider_store,
      recovery: :refresh_from_provider_health_ref,
      replay: :do_not_replay_provider_probe,
      stale_read: :bounded_stale_allowed,
      eviction: :health_ttl,
      conflict: :newer_observation_wins,
      redaction: :refs_only
    },
    target_attach_state: %{
      owner: :execution_plane,
      placement: :cloudflare_durable_object,
      recovery: :reauthorize_attach_grant_ref,
      replay: :replay_attach_descriptor_only,
      stale_read: :reject_stale,
      eviction: :target_detach,
      conflict: :attach_grant_revision_wins,
      redaction: :refs_only
    },
    connector_admission_cache: %{
      owner: :jido_integration,
      placement: :durable_micro_state,
      recovery: :rebuild_from_connector_admission_ref,
      replay: :revalidate_operation_policy_ref,
      stale_read: :reject_stale,
      eviction: :admission_revision_change,
      conflict: :admission_revision_wins,
      redaction: :refs_only
    },
    session_handoff_state: %{
      owner: :agent_session_manager,
      placement: :temporal_history,
      recovery: :rehydrate_refs_only,
      replay: :dedupe_handoff_idempotency_key,
      stale_read: :reject_stale,
      eviction: :handoff_terminal,
      conflict: :single_active_execution_wins,
      redaction: :refs_only
    },
    trace_accumulator: %{
      owner: :AITrace,
      placement: :durable_server,
      recovery: :restore_trace_ref_set,
      replay: :append_once_by_trace_event_ref,
      stale_read: :bounded_stale_allowed,
      eviction: :export_checkpoint,
      conflict: :trace_event_ref_wins,
      redaction: :refs_only
    }
  }

  @raw_material_keys [
    :access_key,
    :api_key,
    :auth,
    :authorization_header,
    :headers,
    :password,
    :private_key,
    :provider_payload,
    :raw_secret,
    :raw_token,
    :secret,
    :target_credentials,
    :token,
    :token_file
  ]

  @spec categories() :: [atom()]
  def categories, do: @categories

  @spec ownership_matrix() :: %{required(atom()) => map()}
  def ownership_matrix, do: @policy

  @spec classify(atom() | String.t()) ::
          {:ok, atom()} | {:error, {:unknown_micro_state_category, term()}}
  def classify(category) when is_atom(category) do
    if category in @categories do
      {:ok, category}
    else
      {:error, {:unknown_micro_state_category, category}}
    end
  end

  def classify(category) when is_binary(category) do
    case Map.fetch(@category_lookup, category) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:unknown_micro_state_category, category}}
    end
  end

  @spec recovery_receipt(atom() | String.t(), map() | keyword()) ::
          {:ok, Receipt.t()}
          | {:error, {:unknown_micro_state_category, term()}}
          | {:error, {:missing_micro_state_refs, [atom()]}}
          | {:error, {:forbidden_micro_state_material, [atom()]}}
  def recovery_receipt(category, attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with {:ok, category} <- classify(category),
         :ok <- reject_raw_material(attrs),
         :ok <- require_refs(attrs) do
      policy = Map.fetch!(@policy, category)

      {:ok,
       struct!(
         Receipt,
         Map.merge(policy, %{
           category: category,
           state_ref: Map.fetch!(attrs, :state_ref),
           tenant_ref: Map.fetch!(attrs, :tenant_ref),
           trace_ref: Map.fetch!(attrs, :trace_ref)
         })
       )}
    end
  end

  @spec validate_stale_read(Receipt.t(), :fresh | :stale) ::
          :ok | {:error, {:stale_read_rejected, atom()}}
  def validate_stale_read(%Receipt{stale_read: :reject_stale, category: category}, :stale) do
    {:error, {:stale_read_rejected, category}}
  end

  def validate_stale_read(%Receipt{}, freshness) when freshness in [:fresh, :stale], do: :ok

  defp reject_raw_material(attrs) do
    blocked = Enum.filter(@raw_material_keys, &Map.has_key?(attrs, &1))

    case blocked do
      [] -> :ok
      keys -> {:error, {:forbidden_micro_state_material, keys}}
    end
  end

  defp require_refs(attrs) do
    missing =
      [:state_ref, :tenant_ref, :trace_ref]
      |> Enum.reject(fn key -> present?(Map.get(attrs, key)) end)

    case missing do
      [] -> :ok
      keys -> {:error, {:missing_micro_state_refs, keys}}
    end
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {normalize_key(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_key(key) do
    Enum.find([:state_ref, :tenant_ref, :trace_ref] ++ @raw_material_keys, key, fn field ->
      Atom.to_string(field) == key
    end)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?(_value), do: true
end
