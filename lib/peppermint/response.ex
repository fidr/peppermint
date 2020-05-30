defmodule Peppermint.Response do
  @moduledoc """
  Response struct
  """

  @type t :: %__MODULE__{}
  defstruct body: nil, headers: [], status: nil
end
