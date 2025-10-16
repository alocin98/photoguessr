defmodule PhotoguessrWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PhotoguessrWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-950 via-slate-900 to-slate-950 text-slate-100">
      <header class="mx-auto flex w-full max-w-6xl items-center justify-between px-6 py-8 sm:px-10">
      </header>

      <main class="mx-auto w-full max-w-6xl px-6 pb-16 sm:px-10">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed inset-x-0 top-6 z-50 flex justify-center px-4"
    >
      <div class="flex w-full max-w-sm flex-col gap-3">
        <.flash kind={:info} flash={@flash} />
        <.flash kind={:error} flash={@flash} />

        <.flash
          id="client-error"
          kind={:error}
          title={gettext("We can't find the internet")}
          phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
          phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
          hidden
        >
          {gettext("Attempting to reconnect")}
          <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
        </.flash>

        <.flash
          id="server-error"
          kind={:error}
          title={gettext("Something went wrong!")}
          phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
          phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
          hidden
        >
          {gettext("Attempting to reconnect")}
          <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
        </.flash>
      </div>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-1 rounded-full border border-white/10 bg-white/5 px-1 py-1 text-xs text-slate-300 backdrop-blur-sm">
      <button
        class="flex items-center gap-1 rounded-full px-3 py-1 transition hover:bg-white/10 hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-80" /> System
      </button>
      <button
        class="flex items-center gap-1 rounded-full px-3 py-1 transition hover:bg-white/10 hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-80" /> Light
      </button>
      <button
        class="flex items-center gap-1 rounded-full px-3 py-1 transition hover:bg-white/10 hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-80" /> Dark
      </button>
    </div>
    """
  end
end
