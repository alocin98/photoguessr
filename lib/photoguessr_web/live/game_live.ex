defmodule PhotoguessrWeb.GameLive do
  use PhotoguessrWeb, :live_view

  alias Ecto.UUID
  alias Photoguessr.GameServer
  alias PhotoguessrWeb.Endpoint
  alias Phoenix.LiveView
  alias MIME

  @admin_password "isweariamuptonogood"

  @impl true
  def mount(_params, session, socket) do
    player_id = session["player_id"] || raise("player_id missing from session")
    player_name = session["player_name"] || raise("player_name missing from session")

    {:ok, initial_view} = GameServer.join(player_id, player_name)

    socket =
      socket
      |> assign(:player_id, player_id)
      |> assign(:player_name, player_name)
      |> assign(:game, initial_view)
      |> assign(:now, DateTime.utc_now())
      |> assign(:submission_location, nil)
      |> assign(:show_admin_modal, false)
      |> assign(:guess_error, nil)
      |> assign_new(:submission_form, fn -> to_form(%{}, as: :submission) end)
      |> assign_new(:admin_form, fn -> to_form(%{}, as: :admin) end)
      |> allow_upload(:photo,
        accept: ~w(image/jpeg image/png image/webp image/heic image/heif),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true
      )

    if connected?(socket) do
      GameServer.subscribe()
      :timer.send_interval(1000, :tick)
    end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    assigns = assign_new(assigns, :current_scope, fn -> nil end)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-12">
        <section class="rounded-3xl border border-slate-200 bg-gradient-to-br from-slate-900 via-slate-900 to-slate-800 px-6 py-8 text-slate-100 shadow-2xl shadow-slate-900/40 sm:px-10">
          <div class="flex flex-col gap-8 lg:flex-row lg:items-start">
            <div class="flex-1 space-y-6">
              <div class="flex items-center gap-4">
                <div class="rounded-full bg-slate-800/70 px-4 py-2">
                  <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Welcome player</p>
                  <p class="mt-1 text-lg font-semibold text-white">{@player_name}</p>
                </div>
                <span class={[
                  "inline-flex items-center rounded-full px-4 py-2 text-sm font-semibold capitalize",
                  stage_badge_class(@game.stage)
                ]}>
                  {stage_label(@game.stage)}
                </span>
              </div>

              <div class="space-y-2">
                <h1 class="text-3xl font-semibold leading-tight text-white sm:text-4xl">
                  PhotoGuessr Arena
                </h1>
                <p class="max-w-2xl text-base text-slate-300 sm:text-lg">
                  Upload your most deceptive travel photos, mark their true location, then challenge friends
                  to pinpoint the spot within sixty thrilling seconds. Accuracy unlocks points, flair earns bragging rights.
                </p>
              </div>

              <div class="grid gap-4 sm:grid-cols-2">
                <div class="rounded-2xl border border-slate-700/70 bg-slate-800/60 p-4">
                  <p class="text-xs uppercase tracking-[0.35em] text-slate-400">Players</p>
                  <p class="mt-2 text-3xl font-semibold text-white">{length(@game.players)}</p>
                  <p class="mt-3 text-sm text-slate-300">
                    Invite friends to upload a photo so each round feels like a new world to explore.
                  </p>
                </div>
                <div class="rounded-2xl border border-slate-700/70 bg-slate-800/60 p-4">
                  <p class="text-xs uppercase tracking-[0.35em] text-slate-400">Rounds Ready</p>
                  <p class="mt-2 text-3xl font-semibold text-white">
                    {total_rounds(@game)}
                  </p>
                  <p class="mt-3 text-sm text-slate-300">
                    Each uploaded photo becomes a round. The host launches a synchronized guessing sprint.
                  </p>
                </div>
              </div>

              <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
                <%= if @game.admin_id == @player_id do %>
                  <span class="inline-flex items-center gap-2 rounded-full bg-emerald-500/10 px-4 py-2 text-sm font-semibold text-emerald-300">
                    <.icon name="hero-star" class="size-4" /> You are the host
                  </span>
                  <button
                    :if={@game.stage == :lobby}
                    id="start-game"
                    type="button"
                    class={[
                      "group flex items-center gap-2 rounded-full px-5 py-2 text-sm font-semibold transition hover:scale-[1.02]",
                      lobby_ready?(@game) &&
                        "bg-emerald-500 text-white shadow-lg shadow-emerald-500/30 hover:bg-emerald-400",
                      !lobby_ready?(@game) && "cursor-not-allowed bg-slate-700 text-slate-400"
                    ]}
                    phx-click="start_game"
                    disabled={!lobby_ready?(@game)}
                  >
                    <.icon
                      name="hero-play-solid"
                      class="size-4 transition group-hover:translate-x-0.5"
                    /> Launch game
                  </button>
                  <button
                    :if={@game.stage == :final}
                    id="reset-game"
                    type="button"
                    class="group flex items-center gap-2 rounded-full bg-slate-200 px-5 py-2 text-sm font-semibold text-slate-900 transition hover:bg-white"
                    phx-click="reset_game"
                  >
                    <.icon name="hero-arrow-path" class="size-4" /> Reset for a new match
                  </button>
                <% else %>
                  <button
                    :if={@game.stage == :lobby}
                    id="claim-host"
                    type="button"
                    class="flex items-center gap-2 rounded-full bg-white/10 px-5 py-2 text-sm font-semibold text-white transition hover:bg-white/20"
                    phx-click="open_admin_modal"
                  >
                    <.icon name="hero-lock-open" class="size-4" /> Become host
                  </button>
                  <span
                    :if={@game.admin_id && @game.admin_id != @player_id}
                    class="inline-flex items-center gap-2 rounded-full bg-amber-500/15 px-4 py-2 text-sm font-semibold text-amber-200"
                  >
                    <.icon name="hero-user" class="size-4" /> Host: {admin_name(@game)}
                  </span>
                <% end %>
              </div>
            </div>

            <aside class="w-full max-w-sm rounded-3xl border border-slate-700/70 bg-slate-800/60 p-6 shadow-2xl shadow-slate-900/40">
              <div class="flex items-center justify-between">
                <p class="text-xs uppercase tracking-[0.35em] text-slate-400">Scoreboard</p>
                <p
                  :if={@game.stage in [:final, {:reveal, 0, 0}, {:round, 0, 0}]}
                  class="text-xs font-semibold text-slate-300"
                >
                  {scoreboard_title(@game.stage)}
                </p>
              </div>
              <ol class="mt-4 space-y-2">
                <li
                  :for={{entry, index} <- Enum.with_index(@game.scoreboard, 1)}
                  class={[
                    "flex items-center justify-between rounded-2xl border px-4 py-3 transition",
                    entry.id == @player_id &&
                      "border-emerald-500/60 bg-emerald-500/10 text-emerald-100 shadow-lg shadow-emerald-500/20",
                    entry.id != @player_id && "border-slate-700/70 bg-slate-900/30 text-slate-200"
                  ]}
                >
                  <div class="flex items-center gap-3">
                    <div class="flex size-8 items-center justify-center rounded-full bg-slate-700/60 text-xs font-semibold">
                      {index}
                    </div>
                    <div>
                      <p class="text-sm font-semibold">{entry.name}</p>
                      <p class="text-xs text-slate-400">Score {entry.score}</p>
                    </div>
                  </div>
                  <.icon name="hero-trophy" class={trophy_icon_class(index)} />
                  <button
                    :if={is_admin(@game, @player_id) && entry.id != @player_id}
                    type="button"
                    class="rounded-full bg-slate-700/60 p-2 text-slate-400 transition hover:bg-slate-700/80 hover:text-slate-200"
                    phx-click="remove_player"
                    phx-value-player-id={entry.id}
                    title={"Remove #{entry.name} from game"}
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </li>
              </ol>
            </aside>
          </div>
        </section>

        <section :if={@game.stage == :lobby} class="grid gap-8 lg:grid-cols-[1.2fr_1fr]">
          <div class="space-y-6 rounded-3xl border border-slate-200 bg-white p-8 shadow-xl shadow-slate-500/10">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-2xl font-semibold text-slate-900">Upload your photo</h2>
                <p class="mt-1 text-sm text-slate-500">
                  Drop an image, place its real location, and add it to the shared round pool.
                </p>
              </div>
              <span class="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
                Step 1
              </span>
            </div>

            <.form
              :if={!submission_limit?(@game)}
              for={@submission_form}
              phx-submit="save_submission"
              phx-change="validate_submission"
              id="submission-form"
              class="space-y-6"
            >
              <div
                phx-drop-target={@uploads.photo.ref}
                class={[
                  "group relative flex flex-col items-center justify-center rounded-2xl border border-dashed border-slate-300 px-6 py-10 text-center transition"
                ]}
              >
                <.icon name="hero-photo" class="size-10 text-slate-400 group-hover:text-slate-500" />
                <p class="mt-4 text-base font-semibold text-slate-700">
                  Drag & drop or click to upload
                </p>
                <p class="mt-2 text-sm text-slate-500">
                  High-resolution JPEG, PNG, or WebP up to 10MB. Only one photo per game is allowed.
                </p>
                <.live_file_input class="bg-slate-400 rounded p-2" upload={@uploads.photo} />
                <div
                  :for={entry <- @uploads.photo.entries}
                  class="mt-6 w-full max-w-md overflow-hidden rounded-xl border border-slate-200 bg-white text-left shadow-sm"
                >
                  <div class="flex items-center justify-between border-b border-slate-100 px-4 py-2">
                    <progress value={entry.progress} max="100">{entry.progress}% </progress>
                    <p class="text-sm font-semibold text-slate-700">{entry.client_name}</p>

                    <button
                      type="button"
                      class="text-xs font-semibold text-rose-500 transition hover:text-rose-400"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                    >
                      Remove
                    </button>
                  </div>
                  <div class="px-4 py-3 text-sm text-slate-500">
                    {human_size(entry.client_size)} &middot; {String.upcase(entry.client_type || "")}
                  </div>
                </div>
              </div>

              <div class="space-y-4">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-semibold text-slate-700">Mark the real location</p>
                    <p class="text-xs text-slate-500">
                      Click anywhere on the map to place the origin of your photo.
                    </p>
                  </div>
                  <div
                    :if={@submission_location}
                    class="rounded-full bg-slate-900 px-4 py-2 text-xs font-semibold text-white"
                  >
                    {format_coords(@submission_location)}
                  </div>
                </div>
                <div
                  id="submission-map"
                  phx-update="ignore"
                  phx-hook="WorldMap"
                  data-mode="submission"
                  data-marker-lat={@submission_location && @submission_location.lat}
                  data-marker-lng={@submission_location && @submission_location.lng}
                  data-center-lat={coords_value(@submission_location, :lat, 20.0)}
                  data-center-lng={coords_value(@submission_location, :lng, 0.0)}
                  data-zoom="2"
                  data-controls="true"
                  class="relative h-80 w-full overflow-hidden rounded-2xl border border-slate-200 bg-slate-950"
                >
                  <div class="pointer-events-none absolute left-4 top-4 z-10 rounded-full bg-slate-900/70 px-3 py-1 text-xs font-semibold uppercase tracking-[0.25em] text-slate-200">
                    Click to set location
                  </div>
                </div>
              </div>

              <div class="flex items-center justify-between">
                <p class="text-sm text-slate-500">
                  Ready? Save to add this round to the upcoming game. You only need one photo per match.
                </p>
                <button
                  type="submit"
                  class="inline-flex items-center gap-2 rounded-full bg-slate-900 px-5 py-2 text-sm font-semibold text-white transition hover:bg-slate-700"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Save photo
                </button>
              </div>
            </.form>
            <div
              :if={submission_limit?(@game)}
              class="rounded-2xl border border-emerald-400/50 bg-emerald-500/10 p-6 text-sm text-emerald-700"
            >
              <p class="font-semibold">Great shot!</p>
              <p class="mt-2">
                You have already contributed your photo for this game. Sit tight and get ready to guess your friends' locations.
              </p>
            </div>
          </div>

          <div class="rounded-3xl border border-slate-200 bg-slate-50 p-8 shadow-xl shadow-slate-500/10">
            <h3 class="text-lg font-semibold text-slate-800">Your uploaded rounds</h3>
            <p class="mt-1 text-sm text-slate-500">
              These photos will appear as separate rounds once the game begins.
            </p>
            <div class="mt-6 grid gap-4">
              <div
                :if={Enum.empty?(safe_get(@game.lobby, :submissions, []))}
                class="flex h-32 flex-col items-center justify-center rounded-2xl border border-dashed border-slate-300 bg-white text-center text-sm text-slate-500"
              >
                No submissions yet. Upload at least one photo to make the match interesting.
              </div>
              <article
                :for={submission <- safe_get(@game.lobby, :submissions, [])}
                class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
              >
                <div class="relative h-40 bg-slate-900">
                  <img
                    src={submission.photo_url}
                    alt={"Photo #{submission.filename}"}
                    class="h-full w-full object-cover"
                  />
                  <div class="absolute top-3 left-3 rounded-full bg-black/60 px-3 py-1 text-xs font-semibold text-white">
                    {format_coords(submission.actual)}
                  </div>
                </div>
                <div class="flex items-center justify-between px-4 py-3 text-sm text-slate-600">
                  <p class="font-semibold text-slate-800">{submission.filename}</p>
                  <p class="text-xs uppercase tracking-[0.2em] text-slate-400">Round ready</p>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section :if={match?({:round, _, _}, @game.stage)} class="grid gap-8 lg:grid-cols-[1.2fr_1fr]">
          <div class="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-xl shadow-slate-500/10">
            <div class="relative bg-slate-900">
              <img
                src={@game.round.photo.url}
                alt={"Guess the location of #{@game.round.photo.filename}"}
                class="h-[32rem] w-full object-cover"
              />
              <div class="absolute top-4 left-4 rounded-full bg-black/60 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-white">
                Round {@game.round.index + 1} of {@game.round.total}
              </div>
              <div class="absolute bottom-4 left-4 rounded-full bg-black/60 px-4 py-2 text-sm font-semibold text-white">
                {round_countdown(@game.round.ends_at, @now)}
              </div>
            </div>
            <div class="grid gap-6 p-8">
              <div>
                <h3 class="text-xl font-semibold text-slate-900">Place your best guess</h3>
                <p class="mt-1 text-sm text-slate-600">
                  Click anywhere on the map. You can refine your guess until the timer reaches zero.
                </p>
              </div>
              <div
                id="guess-map"
                phx-update="ignore"
                phx-hook="WorldMap"
                data-mode="guess"
                data-marker-lat={@game.round.guess && @game.round.guess.lat}
                data-marker-lng={@game.round.guess && @game.round.guess.lng}
                data-center-lat={coords_value(@game.round.guess, :lat, 20.0)}
                data-center-lng={coords_value(@game.round.guess, :lng, 0.0)}
                data-player-id={@player_id}
                data-zoom="2"
                data-controls="true"
                class="relative h-96 overflow-hidden rounded-2xl border border-slate-200 bg-slate-950"
              >
                <div class="pointer-events-none absolute right-4 top-4 z-10 rounded-full bg-slate-900/70 px-3 py-1 text-xs font-semibold uppercase tracking-[0.25em] text-slate-200">
                  Drop your pin
                </div>
              </div>
              <div class="flex items-center justify-between rounded-2xl border border-slate-200 bg-slate-50 px-6 py-4 text-sm text-slate-600">
                <div>
                  <p :if={@game.round.guess} class="font-semibold text-slate-900">
                    Guess locked at {format_coords(@game.round.guess)}
                  </p>
                  <p :if={!@game.round.guess} class="font-semibold text-rose-500">
                    No guess placed yet
                  </p>
                  <p class="text-xs text-slate-500">
                    Every guess scores between 0 and 1000 points based on distance to the real spot.
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <div class="size-3 rounded-full bg-emerald-500" />
                  <span class="text-xs font-semibold text-slate-500">Your marker</span>
                </div>
              </div>
            </div>
          </div>

          <div class="rounded-3xl border border-slate-200 bg-slate-50 p-8 shadow-xl shadow-slate-500/10">
            <h3 class="text-lg font-semibold text-slate-800">Live progress</h3>
            <p class="mt-1 text-sm text-slate-500">
              {@game.round.guess_count}
              {if @game.round.guess_count == 1, do: "player has", else: "players have"} submitted a guess.
            </p>
            <div class="mt-6 space-y-4">
              <div
                :for={player <- @game.players}
                class={[
                  "flex items-center justify-between rounded-2xl border px-4 py-3 text-sm font-semibold transition",
                  player_guessed?(@game.round.guess_map, player.id) &&
                    "border-emerald-400 bg-emerald-400/15 text-emerald-700",
                  !player_guessed?(@game.round.guess_map, player.id) &&
                    "border-slate-200 bg-white text-slate-600"
                ]}
              >
                <div class="flex items-center gap-3">
                  <div class={[
                    "size-2 rounded-full",
                    player_guessed?(@game.round.guess_map, player.id) && "bg-emerald-500",
                    !player_guessed?(@game.round.guess_map, player.id) && "bg-slate-300"
                  ]} />
                  <span>{player.name}</span>
                </div>
                <span
                  :if={player_guessed?(@game.round.guess_map, player.id)}
                  class="text-xs font-semibold uppercase tracking-[0.2em]"
                >
                  Locked in
                </span>
                <span
                  :if={!player_guessed?(@game.round.guess_map, player.id)}
                  class="text-xs font-semibold text-rose-500"
                >
                  Pending
                </span>
              </div>
            </div>
          </div>
        </section>

        <section
          :if={match?({:reveal, _, _}, @game.stage)}
          class="grid gap-8 lg:grid-cols-[1.4fr_1fr]"
        >
          <div class="rounded-3xl border border-slate-200 bg-white shadow-xl shadow-slate-500/10">
            <div class="grid gap-6 p-8">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-xs uppercase tracking-[0.35em] text-slate-400">
                    Round {@game.round.index + 1}
                  </p>
                  <h3 class="mt-1 text-2xl font-semibold text-slate-900">Reveal & distances</h3>
                </div>
                <div class="rounded-full bg-slate-900 px-4 py-2 text-xs font-semibold text-white">
                  {if @game.round.actual do
                    format_coords(@game.round.actual)
                  end}
                </div>
              </div>
              <div
                id="reveal-map"
                phx-update="ignore"
                phx-hook="WorldMap"
                data-mode="reveal"
                data-actual-lat={@game.round.actual && @game.round.actual.lat}
                data-actual-lng={@game.round.actual && @game.round.actual.lng}
                data-guesses={Jason.encode!(@game.round.guesses)}
                data-player-id={@player_id}
                data-center-lat={coords_value(@game.round.actual, :lat, 20.0)}
                data-center-lng={coords_value(@game.round.actual, :lng, 0.0)}
                data-zoom="3"
                data-controls="true"
                class="relative h-[28rem] overflow-hidden rounded-2xl border border-slate-200 bg-slate-950"
              >
                <div class="pointer-events-none absolute left-4 top-4 z-10 rounded-full bg-slate-900/70 px-3 py-1 text-xs font-semibold uppercase tracking-[0.25em] text-slate-200">
                  Actual & guesses
                </div>
              </div>
            </div>
          </div>
          <div class="rounded-3xl border border-slate-200 bg-slate-50 p-8 shadow-xl shadow-slate-500/10">
            <h3 class="text-lg font-semibold text-slate-800">Round leaderboard</h3>
            <p class="mt-1 text-sm text-slate-500">
              Points earned this round based on your accuracy.
            </p>
            <div class="mt-6 space-y-4">
              <article
                :for={guess <- @game.round.guesses}
                class={[
                  "rounded-2xl border px-5 py-4 text-sm",
                  guess.player_id == @player_id &&
                    "border-emerald-400 bg-emerald-400/10 text-emerald-700",
                  guess.player_id != @player_id && "border-slate-200 bg-white text-slate-600"
                ]}
              >
                <div class="flex items-center justify-between">
                  <p class="font-semibold text-slate-900">{guess.player_name}</p>
                  <span class="text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">
                    +{guess.points} pts
                  </span>
                </div>
                <div class="mt-2 flex items-center gap-3 text-xs text-slate-500">
                  <span>{guess_distance_text(guess)}</span>
                  <span :if={guess.lat}>&middot;</span>
                  <span :if={guess.lat}>{format_coords(%{lat: guess.lat, lng: guess.lng})}</span>
                </div>
              </article>
            </div>
            <div class="mt-8 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-xs text-slate-500">
              Next round launches in {round_reveal_countdown(@game.reveal_until, @now)} seconds.
            </div>
          </div>
        </section>

        <section
          :if={@game.stage == :final}
          class="rounded-3xl border border-slate-200 bg-white p-10 shadow-xl shadow-slate-500/10"
        >
          <div class="flex flex-col gap-8 lg:flex-row lg:items-start lg:justify-between">
            <div class="flex-1 space-y-4">
              <h2 class="text-3xl font-semibold text-slate-900">Grand tour complete</h2>
              <p class="text-base text-slate-600">
                Thanks for playing! The scoreboard reflects your cumulative accuracy. Ready for another match? Ask the host to reset.
              </p>
              <div class="rounded-2xl border border-slate-200 bg-slate-50 px-6 py-4 text-sm text-slate-500">
                Keep your browser open—the host can refresh the room, keeping everyone together for the next round.
              </div>
            </div>

            <div class="w-full max-w-md space-y-4">
              <article
                :for={{entry, index} <- Enum.with_index(@game.scoreboard, 1)}
                class={[
                  "rounded-3xl border px-6 py-5 text-sm transition",
                  index == 1 &&
                    "border-amber-400 bg-amber-100/40 text-amber-800 shadow-lg shadow-amber-300/30",
                  index == 2 && "border-slate-200 bg-white text-slate-700",
                  index == 3 && "border-slate-200 bg-white text-slate-700",
                  index > 3 && "border-slate-100 bg-slate-50 text-slate-600"
                ]}
              >
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-3">
                    <div class={[
                      "flex size-10 items-center justify-center rounded-full text-sm font-semibold",
                      index == 1 && "bg-amber-500 text-white",
                      index == 2 && "bg-slate-900 text-white",
                      index == 3 && "bg-slate-600 text-white",
                      index > 3 && "bg-slate-200 text-slate-600"
                    ]}>
                      {index}
                    </div>
                    <div>
                      <p class="text-base font-semibold text-slate-900">{entry.name}</p>
                      <p class="text-xs text-slate-500">{entry.score} pts</p>
                    </div>
                  </div>
                  <.icon :if={index == 1} name="hero-crown" class="size-6 text-amber-500" />
                </div>
              </article>
            </div>
          </div>
        </section>

        <div
          :if={@show_admin_modal}
          id="admin-modal"
          class="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/70 backdrop-blur-sm"
        >
          <div class="w-full max-w-md rounded-3xl border border-slate-200 bg-white p-8 shadow-2xl shadow-slate-900/40">
            <div class="flex items-center justify-between">
              <h3 class="text-xl font-semibold text-slate-900">Claim host controls</h3>
              <button
                type="button"
                class="rounded-full bg-slate-100 p-2 text-slate-500 transition hover:bg-slate-200"
                phx-click="close_admin_modal"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
            <p class="mt-2 text-sm text-slate-500">
              Enter the shared password to unlock host controls. Everyone sees who currently manages the game.
            </p>
            <.form for={@admin_form} id="admin-form" class="mt-6 space-y-4" phx-submit="claim_admin">
              <.input
                field={@admin_form[:password]}
                type="password"
                placeholder="Enter host password"
                class="w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 focus:border-slate-500 focus:outline-none focus:ring-2 focus:ring-slate-400/40"
              />
              <button
                type="submit"
                class="flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white transition hover:bg-slate-700"
              >
                <.icon name="hero-key" class="size-5" /> Unlock host controls
              </button>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("save_submission", _params, %{assigns: %{submission_location: nil}} = socket) do
    {:noreply,
     put_flash(socket, :error, "Choose the real location on the map before saving your photo.")}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_submission", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_submission", _params, socket) do
    case ensure_photo_ready(socket) do
      {:ready, socket} ->
        handle_ready_submission(socket)

      {:wait, socket} ->
        {:noreply,
         put_flash(socket, :info, "Upload still processing. Please wait a moment and try again.")}

      {:none, socket} ->
        handle_ready_submission(socket)
    end
  end

  defp handle_ready_submission(socket) do
    case consume_photo(socket) do
      {:ok, filename, photo_url} ->
        submission = %{
          filename: filename,
          photo_url: photo_url,
          lat: socket.assigns.submission_location.lat,
          lng: socket.assigns.submission_location.lng
        }

        IO.puts("Submission: #{inspect(submission)}")

        case GameServer.add_submission(socket.assigns.player_id, submission) do
          {:ok, view} ->
            {:noreply,
             socket
             |> assign(:game, view)
             |> assign(:submission_location, nil)
             |> assign(:submission_form, to_form(%{}, as: :submission))
             |> put_flash(:info, "Photo added to the lobby rounds.")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:game, socket.assigns.game)
             |> put_flash(:error, submission_error_message(reason))}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("set_submission_location", %{"lat" => lat, "lng" => lng}, socket) do
    {:noreply, assign(socket, :submission_location, %{lat: to_float(lat), lng: to_float(lng)})}
  end

  def handle_event("set_guess_location", %{"lat" => lat, "lng" => lng}, socket) do
    params = %{lat: lat, lng: lng}

    case GameServer.submit_guess(socket.assigns.player_id, params) do
      {:ok, view} ->
        {:noreply, assign(socket, :game, view)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Guess could not be recorded. Try again.")}
    end
  end

  def handle_event("start_game", _params, socket) do
    case GameServer.start_game(socket.assigns.player_id) do
      :ok ->
        {:noreply, refresh_game(socket)}

      {:error, :no_submissions} ->
        {:noreply,
         put_flash(socket, :error, "Upload at least one photo before starting the match.")}

      {:error, :not_admin} ->
        {:noreply, put_flash(socket, :error, "Only the host can start the game.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot start game (#{inspect(reason)}).")}
    end
  end

  def handle_event("reset_game", _params, socket) do
    case GameServer.reset(socket.assigns.player_id) do
      :ok ->
        {:noreply, refresh_game(socket)}

      {:error, :not_admin} ->
        {:noreply, put_flash(socket, :error, "Only the host can reset the room.")}
    end
  end

  def handle_event("open_admin_modal", _params, socket) do
    {:noreply, assign(socket, :show_admin_modal, true)}
  end

  def handle_event("close_admin_modal", _params, socket) do
    {:noreply, assign(socket, :show_admin_modal, false)}
  end

  def handle_event("claim_admin", %{"admin" => %{"password" => password}}, socket) do
    if password == @admin_password do
      case GameServer.become_admin(socket.assigns.player_id) do
        :ok ->
          {:noreply,
           socket
           |> assign(:show_admin_modal, false)
           |> refresh_game()
           |> put_flash(:info, "You now control the match.")}

        {:error, :game_in_progress} ->
          {:noreply,
           socket
           |> assign(:show_admin_modal, false)
           |> put_flash(:error, "Host role can only be claimed in the lobby.")}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:show_admin_modal, false)
           |> put_flash(:error, "Unable to assign host role.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Incorrect password.")}
    end
  end

  def handle_event("claim_admin", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_player", %{"player-id" => id}, socket) do
    case GameServer.kick_player(id) do
      :ok ->
        {:noreply, refresh_game(socket)}

      {:error, :not_admin} ->
        {:noreply, put_flash(socket, :error, "Only the host can remove players.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to remove player.")}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  def handle_info({:game_updated, _version}, socket) do
    {:noreply, refresh_game(socket)}
  end

  @impl true
  def terminate(_reason, socket) do
    GameServer.leave(socket.assigns.player_id)
    :ok
  end

  defp refresh_game(socket) do
    case GameServer.view_for(socket.assigns.player_id) do
      {:ok, view} -> assign(socket, :game, view)
      {:error, _} -> socket
    end
  end

  defp coords_value(location, key, default) when key in [:lat, :lng] do
    case location do
      %{^key => value} when is_number(value) -> value
      _ -> default
    end
  end

  defp consume_photo(socket) do
    case consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
           dest = uploaded_file_destination(entry)
           IO.puts(dest)
           File.mkdir_p!(Path.dirname(dest))
           File.cp!(path, dest)

           basename = Path.basename(dest)
           url = Endpoint.static_path("/uploads/#{basename}")

           {:ok, {entry.client_name || basename, url}}
         end) do
      [{filename, photo_url}] ->
        {:ok, filename, photo_url}

      {:postpone, _} ->
        {:error, "Upload still processing. Please wait and try again."}

      [] ->
        {:error, "Upload a photo before saving your round."}
    end
  end

  defp uploaded_file_destination(entry) do
    Path.join(uploads_dir(), unique_upload_name(entry))
  end

  defp uploads_dir do
    :photoguessr
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("static/uploads")
  end

  defp unique_upload_name(entry) do
    ext = extension_from_entry(entry)
    uuid_part = entry.uuid || UUID.generate()
    "#{uuid_part}-#{System.unique_integer([:positive])}#{ext}"
  end

  defp extension_from_entry(entry) do
    cond do
      entry.client_name && Path.extname(entry.client_name) != "" ->
        entry.client_name |> Path.extname() |> String.downcase()

      entry.client_type && MIME.extensions(entry.client_type) != [] ->
        "." <> hd(MIME.extensions(entry.client_type))

      true ->
        ".bin"
    end
  end

  defp submission_error_message(:invalid_submission),
    do: "Photo data is invalid. Please try uploading again."

  defp submission_error_message(:submission_limit),
    do: "You can only contribute one photo per game."

  defp submission_error_message(:invalid_coordinate),
    do: "That location could not be processed. Please drop the pin again."

  defp submission_error_message(:unknown_player),
    do: "We could not identify your session. Refresh and retry."

  defp submission_error_message(:game_in_progress),
    do: "The match already started. Wait for the next lobby to add new rounds."

  defp submission_error_message(_), do: "Something went wrong while saving your photo."

  defp submission_limit?(%{lobby: %{limit_reached: limit}}) when is_boolean(limit), do: limit
  defp submission_limit?(_), do: false

  defp upload_errors?(upload) do
    Enum.any?(upload.entries, &(&1.errors != []))
  end

  defp ensure_photo_ready(socket) do
    case LiveView.uploaded_entries(socket, :photo) do
      {[_ | _], _} ->
        {:ready, socket}

      {[], [_ | _]} ->
        {:wait, socket}

      {[], []} ->
        upload_entries =
          socket.assigns
          |> Map.get(:uploads, %{})
          |> Map.get(:photo)

        cond do
          upload_entries && upload_entries.entries != [] ->
            {:wait, LiveView.force_upload(socket, :photo)}

          true ->
            {:none, socket}
        end
    end
  end

  defp human_size(bytes) when is_integer(bytes) do
    value = bytes / 1_000_000
    formatted = :erlang.float_to_binary(value, decimals: 2)
    formatted <> " MB"
  end

  defp human_size(_), do: "0.00 MB"

  defp format_coords(%{lat: lat, lng: lng}) when is_number(lat) and is_number(lng) do
    "#{Float.round(lat, 2)}°, #{Float.round(lng, 2)}°"
  end

  defp format_coords(_), do: "–"

  defp stage_badge_class(:lobby), do: "bg-sky-500/20 text-sky-200"
  defp stage_badge_class({:round, _, _}), do: "bg-emerald-500/20 text-emerald-200"
  defp stage_badge_class({:reveal, _, _}), do: "bg-amber-500/20 text-amber-200"
  defp stage_badge_class(:final), do: "bg-purple-500/20 text-purple-200"
  defp stage_badge_class(_), do: "bg-slate-700/60 text-slate-200"

  defp stage_label(:lobby), do: "Lobby prep"
  defp stage_label({:round, _, _}), do: "Guess in progress"
  defp stage_label({:reveal, _, _}), do: "Reveal"
  defp stage_label(:final), do: "Match complete"
  defp stage_label(_), do: "Status unknown"

  defp lobby_ready?(%{stage: :lobby, lobby: lobby}) do
    lobby && lobby.total_rounds > 0
  end

  defp lobby_ready?(_), do: false

  defp trophy_icon_class(index) when index <= 3 do
    "size-4 text-amber-300 opacity-80 transition-opacity"
  end

  defp trophy_icon_class(_index), do: "size-4 opacity-0 transition-opacity"

  defp total_rounds(%{lobby: %{total_rounds: total}}) when is_integer(total), do: total

  defp total_rounds(%{round: %{total: total}}) when is_integer(total), do: total

  defp total_rounds(_), do: 0

  defp admin_name(%{admin_id: nil}), do: "None"

  defp admin_name(%{admin_id: admin_id, players: players}) do
    players
    |> Enum.find_value(fn player ->
      if player.id == admin_id, do: player.name, else: nil
    end) || "Host"
  end

  defp is_admin(%{admin_id: admin_id}, id), do: id == admin_id

  defp scoreboard_title({:round, _, _}), do: "Current round"
  defp scoreboard_title({:reveal, _, _}), do: "Round scores"
  defp scoreboard_title(:final), do: "Final scores"
  defp scoreboard_title(_), do: "Live totals"

  defp guess_distance_text(%{distance_km: distance}) when is_number(distance) do
    formatted = :erlang.float_to_binary(distance, decimals: 2)
    "#{formatted} km away"
  end

  defp guess_distance_text(_), do: "No guess submitted"

  defp round_countdown(nil, _now), do: "Waiting"

  defp round_countdown(ends_at, now) do
    case DateTime.diff(ends_at, now, :second) do
      diff when diff <= 0 -> "Time's up"
      diff -> "#{diff}s remaining"
    end
  end

  defp round_reveal_countdown(nil, _), do: "0"

  defp round_reveal_countdown(reveal_until, now) do
    diff = max(DateTime.diff(reveal_until, now, :second), 0)
    Integer.to_string(diff)
  end

  defp player_guessed?(guesses, player_id) do
    Map.has_key?(guesses, player_id)
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp safe_get(nil, _key, default), do: default
  defp safe_get(map, key, default), do: Map.get(map, key, default)
end
