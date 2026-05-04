defmodule DurableServer.StoredState do
  @moduledoc false

  alias DurableServer.GovernedAuthority
  alias DurableServer.Meta

  defstruct key: nil,
            prefix: nil,
            state: nil,
            meta: nil,
            vsn: nil,
            etag: nil

  @type t :: %__MODULE__{
          key: String.t() | nil,
          prefix: String.t() | nil,
          state: term(),
          meta: Meta.t() | nil,
          vsn: pos_integer() | nil,
          etag: String.t() | nil
        }

  def to_storage_term(%__MODULE__{vsn: vsn, state: state, meta: %Meta{} = meta}) do
    %{
      vsn: vsn,
      state: state,
      meta: Meta.to_storage_term(meta)
    }
  end

  def to_object_store_term(%__MODULE__{vsn: vsn, state: state, meta: %Meta{} = meta}) do
    %{
      "vsn" => vsn,
      "state" => state,
      "meta" => Meta.encode_to_binary(meta)
    }
  end

  def from_storage_term(term, opts \\ [])

  def from_storage_term(%__MODULE__{} = stored_state, opts) do
    case normalize_meta(stored_state.meta) do
      {:ok, meta} ->
        maybe_validate_governed(
          %__MODULE__{
            vsn: stored_state.vsn,
            state: stored_state.state,
            meta: meta
          },
          opts
        )

      {:error, _reason} = error ->
        error
    end
  end

  def from_storage_term(%{vsn: vsn, state: state, meta: meta_term} = term, opts)
      when map_size(term) == 3 do
    case normalize_meta(meta_term) do
      {:ok, meta} ->
        maybe_validate_governed(
          %__MODULE__{
            vsn: vsn,
            state: state,
            meta: meta
          },
          opts
        )

      {:error, _reason} = error ->
        error
    end
  end

  def from_storage_term(_, _opts), do: :not_stored_state

  def from_object_store_term(term, opts \\ [])

  def from_object_store_term(
        %{"vsn" => vsn, "state" => state, "meta" => meta_binary} = term,
        opts
      )
      when map_size(term) == 3 and is_binary(meta_binary) do
    %__MODULE__{
      vsn: vsn,
      state: state,
      meta: Meta.decode_from_binary(meta_binary, %{key: nil, prefix: nil})
    }
    |> maybe_validate_governed(opts)
  rescue
    error in [ArgumentError, RuntimeError] -> {:error, error}
  end

  def from_object_store_term(_, _opts), do: :not_stored_state

  defp normalize_meta(%Meta{} = meta) do
    {:ok, %{meta | key: nil, prefix: nil}}
  end

  defp normalize_meta(meta_term) when is_map(meta_term) do
    {:ok, Meta.from_storage_term(meta_term, %{key: nil, prefix: nil})}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp normalize_meta(other) do
    {:error, ArgumentError.exception("invalid stored meta term: #{inspect(other)}")}
  end

  defp maybe_validate_governed(%__MODULE__{} = stored_state, opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:governed_authority])

    case Keyword.get(opts, :governed_authority) do
      nil ->
        {:ok, stored_state}

      authority ->
        {:ok, GovernedAuthority.validate_stored_state!(authority, stored_state)}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end
end
