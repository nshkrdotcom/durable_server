defmodule DurableServer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: DurableServer.RuntimeNames.local_registry()},
      {Registry, keys: :unique, name: DurableServer.RuntimeNames.singleflight_owner_registry()},
      {Registry,
       keys: :duplicate, name: DurableServer.RuntimeNames.singleflight_waiters_registry()},
      %{id: DurableServer.PG, start: {:pg, :start_link, [DurableServer.PG]}},
      {Finch, name: DurableServer.Finch},
      {Task.Supervisor, name: DurableServer.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: DurableServer.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
