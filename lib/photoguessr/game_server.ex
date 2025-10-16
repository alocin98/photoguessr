defmodule Photoguessr.GameServer do
  @moduledoc """
  Coordinates the shared PhotoGuessr game state for every connected player.

  The server stores lobby submissions, manages timed rounds, computes scores,
  and broadcasts state changes to interested LiveViews.
  """

  use GenServer

  alias Photoguessr.Geospatial

  @topic "photoguessr:game"
  @round_seconds 30
  @reveal_seconds 10

  @type coord :: %{lat: float(), lng: float()}

  ## Client API

  @doc """
  Starts the game server under a supervisor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.merge(opts, name: __MODULE__))
  end

  @doc """
  Subscribes the caller to game updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Photoguessr.PubSub, @topic)
  end

  @doc """
  Ensures the player is tracked in the lobby.
  """
  def join(player_id, player_name) do
    GenServer.call(__MODULE__, {:join, player_id, player_name})
  end

  @doc """
  Removes the player from the lobby.
  """
  def leave(player_id) do
    GenServer.cast(__MODULE__, {:leave, player_id})
  end

  @doc """
  Marks the requesting player as the admin.
  """
  def become_admin(player_id) do
    GenServer.call(__MODULE__, {:become_admin, player_id})
  end

  @doc """
  Adds a submission to the lobby on behalf of a player.
  """
  def add_submission(player_id, submission_params) do
    GenServer.call(__MODULE__, {:add_submission, player_id, submission_params})
  end

  @doc """
  Starts the game, consuming the current lobby submissions into rounds.
  """
  def start_game(player_id) do
    GenServer.call(__MODULE__, {:start_game, player_id})
  end

  @doc """
  Records or updates a player's guess for the active round.
  """
  def submit_guess(player_id, guess_params) do
    GenServer.call(__MODULE__, {:submit_guess, player_id, guess_params})
  end

  @doc """
  Returns a tailored view of the game state for a specific player.
  """
  def view_for(player_id) do
    GenServer.call(__MODULE__, {:view_for, player_id})
  end

  @doc """
  Resets the game, returning to the lobby.
  """
  def reset(player_id) do
    GenServer.call(__MODULE__, {:reset, player_id})
  end

  def kick_player(player_id) do
    GenServer.cast(__MODULE__, {:kick_player, player_id})
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    {:ok,
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
     }}
  end

  @impl true
  def handle_call({:join, player_id, player_name}, _from, state) do
    now = DateTime.utc_now()

    players =
      Map.update(state.players, player_id, new_player(player_id, player_name, now), fn player ->
        player
        |> Map.put(:name, player_name)
        |> Map.put(:last_seen_at, now)
      end)

    new_state = bump_version(%{state | players: players})
    broadcast_change(new_state)

    {:reply, {:ok, view(new_state, player_id)}, new_state}
  end

  def handle_call({:become_admin, player_id}, _from, %{stage: :lobby} = state) do
    if Map.has_key?(state.players, player_id) do
      new_state = bump_version(%{state | admin_id: player_id})
      broadcast_change(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :unknown_player}, state}
    end
  end

  def handle_call({:become_admin, _player_id}, _from, state) do
    {:reply, {:error, :game_in_progress}, state}
  end

  def handle_call({:add_submission, player_id, params}, _from, %{stage: :lobby} = state) do
    with {:ok, submission} <- validate_submission(params),
         {:ok, state} <- persist_submission(state, player_id, submission) do
      {:reply, {:ok, view(state, player_id)}, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:add_submission, _player_id, _params}, _from, state) do
    {:reply, {:error, :game_in_progress}, state}
  end

  def handle_call({:start_game, player_id}, _from, %{stage: :lobby} = state) do
    cond do
      state.admin_id != player_id ->
        {:reply, {:error, :not_admin}, state}

      true ->
        case build_rounds(state.players) do
          [] ->
            {:reply, {:error, :no_submissions}, state}

          rounds ->
            players = reset_scores(state.players)

            new_state =
              state
              |> Map.merge(%{
                players: players,
                rounds: rounds,
                stage: {:round, 0},
                active_round_index: 0
              })
              |> start_round(0)

            broadcast_change(new_state)
            {:reply, :ok, new_state}
        end
    end
  end

  def handle_call({:start_game, _player_id}, _from, state) do
    {:reply, {:error, :game_in_progress}, state}
  end

  def handle_call({:submit_guess, player_id, params}, _from, %{stage: {:round, _}} = state) do
    with {:ok, guess} <- validate_guess(params),
         true <- Map.has_key?(state.players, player_id) do
      new_state = upsert_guess(state, player_id, guess)
      broadcast_change(new_state)
      {:reply, {:ok, view(new_state, player_id)}, new_state}
    else
      false ->
        {:reply, {:error, :unknown_player}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      _ ->
        {:reply, {:error, :invalid_guess}, state}
    end
  end

  def handle_call({:submit_guess, _player_id, _params}, _from, state) do
    {:reply, {:error, :round_not_active}, state}
  end

  def handle_call({:view_for, player_id}, _from, state) do
    {:reply, {:ok, view(state, player_id)}, state}
  end

  def handle_call({:reset, player_id}, _from, %{admin_id: player_id} = state) do
    new_state =
      state
      |> cancel_timers()
      |> Map.merge(%{
        stage: :lobby,
        rounds: [],
        active_round_index: nil,
        round_started_at: nil,
        round_ends_at: nil,
        reveal_until: nil,
        players: reset_for_lobby(state.players)
      })
      |> bump_version()

    broadcast_change(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:reset, _player_id}, _from, state) do
    {:reply, {:error, :not_admin}, state}
  end

  @impl true
  def handle_cast({:leave, player_id}, state) do
    new_state =
      update_in(
        state.players,
        &Map.update(&1, player_id, nil, fn player ->
          Map.put(player, :last_seen_at, DateTime.utc_now())
        end)
      )

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:kick_player, player_id}, state) do
    new_state =
      update_in(
        state.players,
        &Map.delete(&1, player_id)
      )

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:round_timeout, round_id}, %{stage: {:round, index}} = state) do
    case Enum.at(state.rounds, index) do
      %{id: ^round_id} ->
        new_state = finalize_round(state, index)
        broadcast_change(new_state)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:advance_round, previous_index}, %{stage: {:reveal, previous_index}} = state) do
    new_state = advance_round(state, previous_index)
    broadcast_change(new_state)
    {:noreply, new_state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  ## Helpers

  defp new_player(id, name, now) do
    %{
      id: id,
      name: name,
      score: 0,
      submissions: [],
      last_seen_at: now
    }
  end

  defp validate_submission(%{photo_url: photo_url, filename: filename, lat: lat, lng: lng})
       when is_binary(photo_url) and is_binary(filename) do
    with {:ok, lat} <- normalize_coordinate(lat, -90.0, 90.0),
         {:ok, lng} <- normalize_coordinate(lng, -180.0, 180.0) do
      {:ok,
       %{
         id: Ecto.UUID.generate(),
         photo_url: photo_url,
         filename: filename,
         actual: %{lat: lat, lng: lng},
         inserted_at: DateTime.utc_now()
       }}
    end
  end

  defp validate_submission(_invalid), do: {:error, :invalid_submission}

  defp persist_submission(state, player_id, submission) do
    case Map.fetch(state.players, player_id) do
      {:ok, player} ->
        if length(player.submissions) >= 1 do
          {:error, :submission_limit}
        else
          submissions = [submission | player.submissions]
          player = Map.put(player, :submissions, submissions)

          new_state =
            state
            |> put_in([:players, player_id], player)
            |> bump_version()

          broadcast_change(new_state)
          {:ok, new_state}
        end

      :error ->
        {:error, :unknown_player}
    end
  end

  defp build_rounds(players) do
    players
    |> Map.values()
    |> Enum.flat_map(fn player ->
      Enum.map(player.submissions, fn submission ->
        submission
        |> Map.put(:owner_id, player.id)
        |> Map.put(:owner_name, player.name)
        |> Map.put(:guesses, %{})
        |> Map.put(:photo_url, submission.photo_url)
        |> Map.put(:status, :pending)
      end)
    end)
    |> Enum.shuffle()
  end

  defp reset_scores(players) do
    Map.new(players, fn {id, player} ->
      {id,
       player
       |> Map.put(:score, 0)
       |> Map.put(:latest_guess, nil)}
    end)
  end

  defp reset_for_lobby(players) do
    Map.new(players, fn {id, player} ->
      {id,
       player
       |> Map.put(:score, 0)
       |> Map.put(:latest_guess, nil)
       |> Map.put(:submissions, [])}
    end)
  end

  defp start_round(state, index) do
    state = cancel_timers(state)
    now = DateTime.utc_now()
    ends_at = DateTime.add(now, @round_seconds, :second)

    rounds =
      List.update_at(state.rounds, index, fn round ->
        round
        |> Map.put(:status, :active)
        |> Map.put(:started_at, now)
        |> Map.put(:ends_at, ends_at)
      end)

    ref =
      Process.send_after(self(), {:round_timeout, round_id(rounds, index)}, @round_seconds * 1000)

    state
    |> Map.merge(%{
      rounds: rounds,
      stage: {:round, index},
      active_round_index: index,
      round_started_at: now,
      round_ends_at: ends_at,
      reveal_until: nil,
      round_timer_ref: ref,
      reveal_timer_ref: nil
    })
    |> bump_version()
  end

  defp round_id(rounds, index) do
    rounds
    |> Enum.at(index)
    |> Map.fetch!(:id)
  end

  defp upsert_guess(state, player_id, guess) do
    index = state.active_round_index

    rounds =
      List.update_at(state.rounds, index, fn round ->
        guesses =
          Map.update(round.guesses, player_id, guess, fn existing ->
            Map.merge(existing, guess)
          end)

        Map.put(round, :guesses, guesses)
      end)

    state
    |> Map.put(:rounds, rounds)
    |> bump_version()
  end

  defp finalize_round(state, index) do
    state = cancel_round_timer(state)
    round = Enum.at(state.rounds, index)

    {round, players} = compute_round_results(round, state.players)

    rounds = List.replace_at(state.rounds, index, round)
    now = DateTime.utc_now()
    reveal_until = DateTime.add(now, @reveal_seconds, :second)
    ref = Process.send_after(self(), {:advance_round, index}, @reveal_seconds * 1000)

    state
    |> Map.merge(%{
      rounds: rounds,
      players: players,
      stage: {:reveal, index},
      round_started_at: round.started_at,
      round_ends_at: round.ends_at,
      reveal_until: reveal_until,
      reveal_timer_ref: ref
    })
    |> bump_version()
  end

  defp advance_round(state, previous_index) do
    next_index = previous_index + 1

    cond do
      next_index < length(state.rounds) ->
        start_round(state, next_index)

      true ->
        conclude_game(state)
    end
  end

  defp conclude_game(state) do
    state
    |> cancel_timers()
    |> Map.merge(%{
      stage: :final,
      active_round_index: nil,
      round_started_at: nil,
      round_ends_at: nil,
      reveal_until: nil
    })
    |> bump_version()
  end

  defp compute_round_results(round, players) do
    actual = round.actual

    updated_guesses =
      players
      |> Map.keys()
      |> Enum.reduce(round.guesses, fn player_id, guesses ->
        guess = Map.get(guesses, player_id)
        enrich_guess(guesses, player_id, actual, guess)
      end)

    round =
      Map.merge(round, %{
        guesses: updated_guesses,
        status: :complete,
        revealed_at: DateTime.utc_now()
      })

    players =
      Enum.reduce(updated_guesses, players, fn {player_id, guess}, acc ->
        points = Map.get(guess, :points, 0)

        Map.update!(acc, player_id, fn player ->
          player
          |> Map.update(:score, points, &(&1 + points))
          |> Map.put(:latest_guess, guess)
        end)
      end)

    {round, players}
  end

  defp enrich_guess(guesses, player_id, _actual, nil) do
    default = %{
      lat: nil,
      lng: nil,
      submitted_at: nil,
      distance_km: nil,
      points: 0
    }

    Map.put_new(guesses, player_id, default)
  end

  defp enrich_guess(guesses, player_id, actual, guess) do
    distance = Geospatial.distance_km(actual.lat, actual.lng, guess.lat, guess.lng)
    points = points_from_distance(distance)

    enriched =
      guess
      |> Map.put(:distance_km, distance)
      |> Map.put(:points, points)

    Map.put(guesses, player_id, enriched)
  end

  defp points_from_distance(distance_km) do
    raw = :math.exp(-distance_km / 2000) * 1000
    raw |> Float.round(0) |> trunc()
  end

  defp validate_guess(%{lat: lat, lng: lng}) do
    with {:ok, lat} <- normalize_coordinate(lat, -90.0, 90.0),
         {:ok, lng} <- normalize_coordinate(lng, -180.0, 180.0) do
      {:ok,
       %{
         lat: lat,
         lng: lng,
         submitted_at: DateTime.utc_now()
       }}
    end
  end

  defp validate_guess(_invalid), do: {:error, :invalid_guess}

  defp normalize_coordinate(value, min, max) when is_integer(value) do
    normalize_coordinate(value * 1.0, min, max)
  end

  defp normalize_coordinate(value, min, max) when is_float(value) do
    cond do
      value < min -> {:ok, min}
      value > max -> {:ok, max}
      true -> {:ok, value}
    end
  end

  defp normalize_coordinate(value, min, max) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> normalize_coordinate(parsed, min, max)
      _ -> {:error, :invalid_coordinate}
    end
  end

  defp normalize_coordinate(_value, _min, _max), do: {:error, :invalid_coordinate}

  defp view(state, player_id) do
    %{
      stage: stage_descriptor(state),
      admin_id: state.admin_id,
      current_player: Map.get(state.players, player_id),
      players: players_view(state.players),
      lobby: lobby_view(state, player_id),
      round: round_view(state, player_id),
      scoreboard: scoreboard_view(state.players),
      reveal_until: state.reveal_until
    }
  end

  defp stage_descriptor(%{stage: {:round, index}}) do
    {:round, index, index + 1}
  end

  defp stage_descriptor(%{stage: {:reveal, index}}) do
    {:reveal, index, index + 1}
  end

  defp stage_descriptor(%{stage: stage}), do: stage

  defp players_view(players) do
    players
    |> Map.values()
    |> Enum.map(fn player ->
      %{
        id: player.id,
        name: player.name,
        score: player.score,
        submissions_count: length(player.submissions)
      }
    end)
  end

  defp lobby_view(%{stage: :lobby} = state, player_id) do
    my_submissions =
      state.players
      |> Map.get(player_id)
      |> case do
        nil -> []
        player -> player.submissions
      end

    %{
      submissions: my_submissions,
      total_rounds: total_rounds_count(state.players),
      limit_reached: length(my_submissions) >= 1
    }
  end

  defp lobby_view(_state, _player_id), do: nil

  defp total_rounds_count(players) do
    players
    |> Map.values()
    |> Enum.map(&length(&1.submissions))
    |> Enum.sum()
  end

  defp round_view(%{stage: {:round, index}} = state, player_id) do
    round = Enum.at(state.rounds, index)

    %{
      index: index,
      total: length(state.rounds),
      photo: %{url: round.photo_url, filename: round.filename},
      started_at: round.started_at,
      ends_at: round.ends_at,
      guess: Map.get(round.guesses, player_id),
      guess_count: map_size(round.guesses),
      guess_map: round.guesses,
      actual: nil,
      guesses: nil
    }
  end

  defp round_view(%{stage: {:reveal, index}} = state, _player_id) do
    round = Enum.at(state.rounds, index)

    %{
      index: index,
      total: length(state.rounds),
      photo: %{url: round.photo_url, filename: round.filename},
      started_at: round.started_at,
      ends_at: round.ends_at,
      actual: round.actual,
      guesses: reveal_guess_view(round.guesses, state.players),
      guess_count: map_size(round.guesses),
      revealed_at: round.revealed_at
    }
  end

  defp round_view(%{stage: :final} = state, _player_id) do
    %{
      total: length(state.rounds),
      completed: true
    }
  end

  defp round_view(_state, _player_id), do: nil

  defp reveal_guess_view(guesses, players) do
    guesses
    |> Enum.map(fn {player_id, guess} ->
      player = Map.fetch!(players, player_id)

      %{
        player_id: player_id,
        player_name: player.name,
        lat: guess.lat,
        lng: guess.lng,
        distance_km: guess.distance_km,
        points: guess.points
      }
    end)
    |> Enum.sort_by(& &1.points, :desc)
  end

  defp scoreboard_view(players) do
    players
    |> Map.values()
    |> Enum.map(fn player ->
      %{
        id: player.id,
        name: player.name,
        score: player.score
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp bump_version(state) do
    Map.update!(state, :version, &(&1 + 1))
  end

  defp cancel_round_timer(%{round_timer_ref: nil} = state), do: state

  defp cancel_round_timer(%{round_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | round_timer_ref: nil}
  end

  defp cancel_reveal_timer(%{reveal_timer_ref: nil} = state), do: state

  defp cancel_reveal_timer(%{reveal_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | reveal_timer_ref: nil}
  end

  defp cancel_timers(state) do
    state
    |> cancel_round_timer()
    |> cancel_reveal_timer()
  end

  defp broadcast_change(state) do
    Phoenix.PubSub.broadcast(Photoguessr.PubSub, @topic, {:game_updated, state.version})
  end
end
