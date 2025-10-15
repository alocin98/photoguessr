defmodule PhotoguessrWeb.PageController do
  use PhotoguessrWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
