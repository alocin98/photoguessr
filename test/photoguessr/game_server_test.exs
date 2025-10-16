defmodule Photoguessr.GameServerTest do
  use ExUnit.Case, async: false

  alias Photoguessr.GameServer

  @photo_stub "/uploads/test.png"

  setup do
    reset_game_server()
    on_exit(fn -> reset_game_server() end)
    :ok
  end

  test "runs a round and scores guesses" do
    {:ok, _} = GameServer.join("alpha", "Atlas Voyager")
    {:ok, _} = GameServer.join("bravo", "Nebula Scout")

    {:ok, _} =
      GameServer.add_submission("alpha", %{
        filename: "sunrise.png",
        photo_url: @photo_stub,
        lat: 12.0,
        lng: 8.0
      })

    assert :ok = GameServer.become_admin("alpha")
    assert :ok = GameServer.start_game("alpha")

    {:ok, view} = GameServer.view_for("bravo")
    assert match?({:round, _, _}, view.stage)

    {:ok, _} = GameServer.submit_guess("bravo", %{lat: 12.5, lng: 8.5})

    send(GameServer, {:round_timeout, current_round_id()})
    Process.sleep(10)

    {:ok, reveal_view} = GameServer.view_for("bravo")
    assert match?({:reveal, _, _}, reveal_view.stage)

    [%{id: "bravo", score: score_bravo} | _] = reveal_view.scoreboard
    assert score_bravo > 0
  end

  test "reset returns game to lobby and clears scores" do
    {:ok, _} = GameServer.join("alpha", "Host Player")

    {:ok, _} =
      GameServer.add_submission("alpha", %{
        filename: "city.png",
        photo_url: @photo_stub,
        lat: 0.0,
        lng: 0.0
      })

    assert :ok = GameServer.become_admin("alpha")
    assert :ok = GameServer.start_game("alpha")

    send(GameServer, {:round_timeout, current_round_id()})
    Process.sleep(10)

    assert :ok = GameServer.reset("alpha")

    {:ok, lobby_view} = GameServer.view_for("alpha")
    assert lobby_view.stage == :lobby
    assert Enum.all?(lobby_view.scoreboard, &(&1.score == 0))
    assert lobby_view.lobby.limit_reached == false
  end

  test "rejects malformed submissions" do
    {:ok, _} = GameServer.join("alpha", "Atlas Voyager")

    assert {:error, :invalid_coordinate} =
             GameServer.add_submission("alpha", %{
               filename: "bad.png",
               photo_url: @photo_stub,
               lat: nil,
               lng: nil
             })
  end

  test "enforces a single submission per player" do
    {:ok, _} = GameServer.join("alpha", "Atlas Voyager")

    assert {:ok, _} =
             GameServer.add_submission("alpha", %{
               filename: "first.png",
               photo_url: @photo_stub,
               lat: 10.0,
               lng: 10.0
             })

    assert {:error, :submission_limit} =
             GameServer.add_submission("alpha", %{
               filename: "second.png",
               photo_url: @photo_stub,
               lat: 12.0,
               lng: 12.0
             })
  end

  defp current_round_id do
    state = :sys.get_state(GameServer)
    index = state.active_round_index || 0

    case Enum.at(state.rounds, index) do
      nil -> flunk("expected active round but found none in GameServer state")
      round -> Map.fetch!(round, :id)
    end
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
