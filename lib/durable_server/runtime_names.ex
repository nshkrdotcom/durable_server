defmodule DurableServer.RuntimeNames do
  @moduledoc false

  @local_registry DurableServer.LocalRegistry
  @singleflight_owner_registry DurableServer.SingleflightOwnerRegistry
  @singleflight_waiters_registry DurableServer.SingleflightWaitersRegistry

  def local_registry, do: @local_registry
  def singleflight_owner_registry, do: @singleflight_owner_registry
  def singleflight_waiters_registry, do: @singleflight_waiters_registry

  def process_name(supervisor_name, kind) when is_atom(supervisor_name) and is_atom(kind) do
    {:via, Registry, {@local_registry, {supervisor_name, kind}}}
  end

  def new_table!(supervisor_name, kind, opts)
      when is_atom(supervisor_name) and is_atom(kind) and is_list(opts) do
    key = table_key(supervisor_name, kind)

    case :persistent_term.get(key, :undefined) do
      :undefined ->
        create_table!(key, opts)

      table ->
        if table_alive?(table) do
          raise ArgumentError,
                "DurableServer ETS table #{inspect(kind)} already exists for #{inspect(supervisor_name)}"
        else
          create_table!(key, opts)
        end
    end
  end

  def table!(supervisor_name, kind) when is_atom(supervisor_name) and is_atom(kind) do
    case :persistent_term.get(table_key(supervisor_name, kind), :undefined) do
      :undefined ->
        raise ArgumentError,
              "DurableServer ETS table #{inspect(kind)} not found for #{inspect(supervisor_name)}"

      table ->
        table
    end
  end

  def table(supervisor_name, kind) when is_atom(supervisor_name) and is_atom(kind) do
    case :persistent_term.get(table_key(supervisor_name, kind), :undefined) do
      :undefined -> nil
      table -> if table_alive?(table), do: table, else: nil
    end
  end

  def table_alive?(table) do
    :ets.info(table) != :undefined
  rescue
    ArgumentError -> false
  end

  defp create_table!(key, opts) do
    table = :ets.new(__MODULE__, List.delete(opts, :named_table))
    :persistent_term.put(key, table)
    table
  end

  defp table_key(supervisor_name, kind) do
    {__MODULE__, :ets, supervisor_name, kind}
  end
end
