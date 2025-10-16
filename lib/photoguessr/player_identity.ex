defmodule Photoguessr.PlayerIdentity do
  @moduledoc """
  Generates memorable pseudo-random player names.
  """

  @adjectives ~w[
    Adventurous
    Bold
    Breezy
    Clever
    Daring
    Electric
    Fearless
    Glowing
    Golden
    Luminous
    Mystic
    Noble
    Radiant
    Spirited
    Stellar
    Swift
    Vivid
    Whimsical
  ]

  @nouns ~w[
    Aurora
    Beacon
    Cascade
    Comet
    Falcon
    Horizon
    Mirage
    Nebula
    Nomad
    Odyssey
    Oracle
    Phoenix
    Prism
    Ridge
    River
    Summit
    Tempest
    Voyager
  ]

  @doc """
  Returns a two-word display name composed from curated adjective and noun lists.
  """
  @spec generate_name() :: String.t()
  def generate_name do
    adjective = Enum.random(@adjectives)
    noun = Enum.random(@nouns)

    "#{adjective} #{noun}"
  end
end
