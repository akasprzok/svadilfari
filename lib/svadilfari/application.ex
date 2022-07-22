defmodule Svadilfari.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Svadilfari.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Svadilfari.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
