defmodule Photoguessr.Repo do
  use Ecto.Repo,
    otp_app: :photoguessr,
    adapter: Ecto.Adapters.Postgres
end
