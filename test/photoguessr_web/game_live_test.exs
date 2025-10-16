defmodule PhotoguessrWeb.GameLiveTest do
  use PhotoguessrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Photoguessr.GameServer

  setup %{conn: conn} do
    reset_game_server()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{
        "player_id" => "tester",
        "player_name" => "Luminous Echo"
      })

    on_exit(fn -> reset_game_server() end)
    {:ok, conn: conn}
  end

  test "renders lobby sections and highlights the player name", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "h1", "PhotoGuessr Arena")
    assert has_element?(view, "p", "Welcome player")
    assert has_element?(view, "ol li", "Score")
    assert has_element?(view, "#submission-map[data-mode=\"submission\"]")
  end

  test "shows host controls when player is admin", %{conn: conn} do
    {:ok, _} = GameServer.join("tester", "Luminous Echo")
    :ok = GameServer.become_admin("tester")

    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#start-game", "Launch game")
  end

  defp reset_game_server do
    :sys.replace_state(GameServer, fn state ->
      cancel_timer(state.round_timer_ref)
      cancel_timer(state.reveal_timer_ref)

      %{
        players: %{},
        admin_id: nil,
        stage: :lobby,
        rounds: [],
        active_round_index: nil,
        round_started_at: nil,
        round_ends_at: nil,
        reveal_until: nil,
        round_timer_ref: nil,
        reveal_timer_ref: nil,
        version: 0
      }
    end)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end
