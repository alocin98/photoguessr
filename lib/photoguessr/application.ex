defmodule Photoguessr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhotoguessrWeb.Telemetry,
      Photoguessr.Repo,
      {DNSCluster, query: Application.get_env(:photoguessr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Photoguessr.PubSub},
      Photoguessr.GameServer,
      # Start a worker by calling: Photoguessr.Worker.start_link(arg)
      # {Photoguessr.Worker, arg},
      # Start to serve requests, typically the last entry
      PhotoguessrWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Photoguessr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhotoguessrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
