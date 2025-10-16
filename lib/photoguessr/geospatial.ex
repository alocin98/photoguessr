defmodule Photoguessr.Geospatial do
  @moduledoc """
  Provides helpers for working with geographic coordinates.
  """

  @earth_radius_km 6371.0

  @doc """
  Calculates the great-circle distance in kilometers between two latitude/longitude pairs.
  """
  @spec distance_km(float(), float(), float(), float()) :: float()
  def distance_km(lat1, lng1, lat2, lng2) do
    lat1 = to_radians(lat1)
    lat2 = to_radians(lat2)
    delta_lat = lat2 - lat1
    delta_lng = to_radians(lng2 - lng1)

    a =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(lat1) * :math.cos(lat2) * :math.sin(delta_lng / 2) * :math.sin(delta_lng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    Float.round(@earth_radius_km * c, 2)
  end

  defp to_radians(value), do: value * :math.pi() / 180.0
end
