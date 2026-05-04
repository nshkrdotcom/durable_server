defmodule DurableServer.GovernedAuthority do
  @moduledoc """
  Governed authority metadata for durable recovery and heartbeat persistence.

  Standalone DurableServer configurations can continue to persist application
  state exactly as before. Governed configurations pass refs that identify the
  authority, credential, target, service identity, cursor authority, and
  redaction policy without allowing recovered state or node heartbeats to carry
  raw authority material.
  """

  alias DurableServer.StoredState

  @redaction_marker "[REDACTED]"

  @required_refs [
    :authority_ref,
    :credential_ref,
    :target_ref,
    :service_identity_ref,
    :cursor_authority_ref
  ]

  @optional_refs [
    :lease_ref,
    :provider_health_ref,
    :trace_redaction_ref
  ]

  @raw_authority_fields [
    "access_key",
    "api_key",
    "auth",
    "authorization",
    "credential",
    "cursor_authority",
    "headers",
    "lease",
    "password",
    "private_key",
    "provider_health",
    "secret",
    "service_identity",
    "target_grant",
    "token",
    "trace_accumulator"
  ]

  @env_authority_fields [
    "ACCESS_KEY",
    "API_KEY",
    "AUTH",
    "AUTHORIZATION",
    "CREDENTIAL",
    "PASSWORD",
    "PRIVATE_KEY",
    "SECRET",
    "TOKEN"
  ]

  @type t :: %__MODULE__{
          authority_ref: String.t(),
          credential_ref: String.t(),
          target_ref: String.t(),
          service_identity_ref: String.t(),
          cursor_authority_ref: String.t(),
          lease_ref: String.t() | nil,
          provider_health_ref: String.t() | nil,
          trace_redaction_ref: String.t() | nil,
          redaction_values: [String.t()],
          metadata: map()
        }

  @enforce_keys [
    :authority_ref,
    :credential_ref,
    :target_ref,
    :service_identity_ref,
    :cursor_authority_ref,
    :redaction_values,
    :metadata
  ]
  @derive {Inspect, except: [:redaction_values]}
  defstruct [
    :authority_ref,
    :credential_ref,
    :target_ref,
    :service_identity_ref,
    :cursor_authority_ref,
    :lease_ref,
    :provider_health_ref,
    :trace_redaction_ref,
    :redaction_values,
    :metadata
  ]

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = authority), do: validate!(authority)

  def new!(opts) when is_list(opts) do
    opts
    |> Map.new()
    |> new!()
  end

  def new!(%{} = opts) do
    refs =
      Enum.into(@required_refs ++ @optional_refs, %{}, fn key ->
        {key, ref_value(opts, key)}
      end)

    metadata =
      refs
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    %__MODULE__{
      authority_ref: Map.fetch!(refs, :authority_ref),
      credential_ref: Map.fetch!(refs, :credential_ref),
      target_ref: Map.fetch!(refs, :target_ref),
      service_identity_ref: Map.fetch!(refs, :service_identity_ref),
      cursor_authority_ref: Map.fetch!(refs, :cursor_authority_ref),
      lease_ref: Map.fetch!(refs, :lease_ref),
      provider_health_ref: Map.fetch!(refs, :provider_health_ref),
      trace_redaction_ref: Map.fetch!(refs, :trace_redaction_ref),
      redaction_values: normalize_redaction_values(fetch_value(opts, :redaction_values, [])),
      metadata: metadata
    }
    |> validate!()
  end

  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = authority) do
    Enum.each(@required_refs, fn key ->
      authority
      |> Map.fetch!(key)
      |> validate_ref!(key)
    end)

    Enum.each(@optional_refs, fn key ->
      case Map.fetch!(authority, key) do
        nil -> :ok
        value -> validate_ref!(value, key)
      end
    end)

    authority
  end

  @spec validate_stored_state!(nil | t() | map() | keyword(), term()) :: term()
  def validate_stored_state!(nil, %StoredState{} = stored_state), do: stored_state

  def validate_stored_state!(authority, %StoredState{} = stored_state) do
    authority = new!(authority)
    validate_recovered!(authority, stored_state.state, ["state"])
    validate_recovered!(authority, stored_state.meta, ["meta"])
    stored_state
  end

  @spec validate_recovered!(nil | t() | map() | keyword(), term(), [String.t()]) :: :ok
  def validate_recovered!(nil, _value, _path), do: :ok

  def validate_recovered!(authority, value, path) do
    authority = new!(authority)
    do_validate_recovered!(authority, value, path)
  end

  @spec validate_heartbeat_env_vars!(nil | t() | map() | keyword(), map()) :: :ok
  def validate_heartbeat_env_vars!(nil, _env_vars), do: :ok

  def validate_heartbeat_env_vars!(authority, env_vars) when is_map(env_vars) do
    _authority = new!(authority)

    Enum.each(env_vars, fn {name, _value} ->
      name = to_string(name)

      if env_authority_field?(name) do
        raise ArgumentError,
              "governed heartbeat env var #{name} looks authority-bearing; use a non-secret placement key"
      end
    end)
  end

  @spec validate_heartbeat_meta!(nil | t() | map() | keyword(), map() | nil) :: :ok
  def validate_heartbeat_meta!(nil, _heartbeat_meta), do: :ok
  def validate_heartbeat_meta!(_authority, nil), do: :ok

  def validate_heartbeat_meta!(authority, heartbeat_meta) when is_map(heartbeat_meta) do
    validate_recovered!(authority, heartbeat_meta, ["heartbeat_meta"])
  end

  @spec redact(nil | t() | map() | keyword(), String.t()) :: String.t()
  def redact(nil, value) when is_binary(value), do: value

  def redact(authority, value) when is_binary(value) do
    %{redaction_values: values} = new!(authority)

    Enum.reduce(values, value, fn secret, redacted ->
      String.replace(redacted, secret, @redaction_marker)
    end)
  end

  defp do_validate_recovered!(authority, %{} = map, path) do
    if Map.has_key?(map, :__struct__) do
      do_validate_recovered!(authority, Map.from_struct(map), path)
    else
      validate_recovered_map!(authority, map, path)
    end
  end

  defp do_validate_recovered!(authority, list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.each(fn {value, index} ->
      do_validate_recovered!(authority, value, [Integer.to_string(index) | path])
    end)
  end

  defp do_validate_recovered!(%__MODULE__{redaction_values: values}, value, path)
       when is_binary(value) do
    case Enum.find(values, fn secret -> String.contains?(value, secret) end) do
      nil ->
        :ok

      _secret ->
        raise ArgumentError,
              "governed recovery cannot restore redaction-protected value at #{format_path(path)}"
    end
  end

  defp do_validate_recovered!(_authority, _value, _path), do: :ok

  defp validate_recovered_map!(authority, map, path) do
    Enum.each(map, fn {key, value} ->
      key_string = key_to_string(key)

      if raw_authority_field?(key_string) do
        raise ArgumentError,
              "governed recovery cannot restore raw authority field #{key_string} at #{format_path([key_string | path])}; use ref metadata"
      end

      do_validate_recovered!(authority, value, [key_string | path])
    end)
  end

  defp raw_authority_field?(key) when is_binary(key) do
    normalized = String.downcase(key)

    if String.ends_with?(normalized, "_ref") do
      false
    else
      Enum.any?(@raw_authority_fields, fn field ->
        bounded_field_match?(normalized, field)
      end)
    end
  end

  defp env_authority_field?(name) when is_binary(name) do
    normalized = String.upcase(name)

    Enum.any?(@env_authority_fields, fn field ->
      bounded_field_match?(normalized, field)
    end)
  end

  defp bounded_field_match?(value, field) when is_binary(value) and is_binary(field) do
    value == field or String.starts_with?(value, field <> "_") or
      String.ends_with?(value, "_" <> field) or String.contains?(value, "_" <> field <> "_")
  end

  defp ref_value(opts, key) when is_map(opts) and is_atom(key) do
    if key in @required_refs do
      opts |> fetch_value(key, nil) |> validate_ref!(key)
    else
      optional_string(opts, key)
    end
  end

  defp validate_ref!(value, _key) when is_binary(value) and value != "", do: value

  defp validate_ref!(value, key) do
    raise ArgumentError,
          "governed authority #{inspect(key)} must be a non-empty string, got: #{inspect(value)}"
  end

  defp optional_string(opts, key) when is_map(opts) and is_atom(key) do
    case fetch_value(opts, key, nil) do
      nil ->
        nil

      value when is_binary(value) and value != "" ->
        value

      value ->
        raise ArgumentError,
              "governed authority #{inspect(key)} must be nil or a non-empty string, got: #{inspect(value)}"
    end
  end

  defp normalize_redaction_values(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_redaction_values(value) when is_binary(value) and value != "", do: [value]
  defp normalize_redaction_values(_), do: []

  defp fetch_value(map, key, default) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(map, Atom.to_string(key), default)
    end
  end

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key), do: inspect(key)

  defp format_path(path) do
    path
    |> Enum.reverse()
    |> Enum.join(".")
  end
end
