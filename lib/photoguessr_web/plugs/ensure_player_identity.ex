defmodule PhotoguessrWeb.Plugs.EnsurePlayerIdentity do
  @moduledoc """
  Guarantees every visitor has a stable identifier and display name stored in a cookie.
  """

  import Plug.Conn

  alias Photoguessr.PlayerIdentity

  @cookie_key "_photoguessr_player_name"
  @cookie_opts [max_age: 365 * 24 * 60 * 60, http_only: false, same_site: "Lax"]

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    {conn, name} =
      case conn.cookies[@cookie_key] do
        nil ->
          name = PlayerIdentity.generate_name()
          {put_resp_cookie(conn, @cookie_key, name, @cookie_opts), name}

        existing_name when is_binary(existing_name) ->
          {put_resp_cookie(conn, @cookie_key, existing_name, @cookie_opts), existing_name}
      end

    conn
    |> ensure_session_id()
    |> put_session(:player_name, name)
  end

  defp ensure_session_id(conn) do
    case get_session(conn, :player_id) do
      nil ->
        id = Ecto.UUID.generate()
        put_session(conn, :player_id, id)

      _existing ->
        conn
    end
  end
end
