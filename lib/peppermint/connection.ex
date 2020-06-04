defmodule Peppermint.Connection do
  use GenServer

  @moduledoc """
  Reusable process to handle a connection.

  - Executes requests in parallel on HTTP/2 (multiplexing). Note: since the request function is a
    GenServer call, to have async requests, they'll need to come from multiple processes.
  - Executes requests sequentially on HTTP/1

  Example:

      {:ok, conn} = Peppermint.Connection.open("http://httpbin.org")
      {:ok, response} = Peppermint.Connection.request(conn, :get, "/get?foo=bar")
      {:ok, response} = Peppermint.Connection.request(conn, :post, "/post", params: %{foo: "bar"})
      :ok = Peppermint.Connection.close(conn)

  """

  @doc """
  Open a connection to a host
  """
  @spec open(String.t(), keyword) :: {:ok, pid}
  def open(url, options \\ []) do
    GenServer.start_link(__MODULE__, {url, options})
  end

  @doc """
  Close the connection
  """
  @spec close(pid) :: :ok
  def close(connection) do
    GenServer.cast(connection, :close)
  end

  @doc """
  Execute a request and wait for the response
  """
  @spec request(pid, atom, String.t(), keyword) ::
          {:ok, Peppermint.Reponse.t()} | {:error, Mint.Types.error()} | {:error, :timeout}
  def request(connection, method, path, options \\ []) do
    GenServer.call(connection, {:request, method, path, options}, :infinity)
  end

  # Implementation

  @doc false
  def init({url, options}) do
    {:ok, %{conn: nil, requests: %{}, refs: %{}, url: url, options: options}, {:continue, :connect}}
  end

  @doc false
  def handle_continue(:connect, state) do
    {:noreply, ensure_connection(state)}
  end

  @doc false
  # Handle HTTP1 requests in sequence
  def handle_call({:request, method, path, options}, _from, %{conn: %Mint.HTTP1{}} = state) do
    %{conn: conn} = ensure_connection(state)

    case Peppermint.execute(conn, method, path, options) do
      {:ok, conn, request_ref} ->
        case Peppermint.receive_response(conn, request_ref, options) do
          {:ok, conn, response} ->
            {:reply, {:ok, response}, %{state | conn: conn}}

          {:error, conn, reason} ->
            {:reply, {:error, reason}, %{state | conn: conn}}
        end

      {:error, conn, reason} ->
        {:reply, {:error, reason}, %{state | conn: conn}}
    end
  end

  @doc false
  # Handle HTTP2 requests simulaniously
  def handle_call({:request, method, path, options}, from, state) do
    %{conn: conn, requests: requests, refs: refs} = ensure_connection(state)

    case Peppermint.execute(conn, method, path, options) do
      {:ok, conn, request_ref} ->
        timeout = Keyword.get(options, :timeout, nil)

        if timeout, do: Process.send_after(self(), {:timeout, request_ref}, timeout)

        {:noreply,
         %{
           state
           | conn: conn,
             requests: Map.put(requests, request_ref, %{}),
             refs: Map.put(refs, request_ref, from)
         }}

      {:error, conn, reason} ->
        {:reply, {:error, reason}, %{state | conn: conn}}
    end
  end

  @doc false
  def handle_cast(:close, %{conn: conn} = state) do
    {:ok, conn} = Peppermint.close(conn)
    {:stop, :normal, %{state | conn: conn}}
  end

  @doc false
  def handle_info({:timeout, request_ref}, %{requests: requests, refs: refs} = state) do
    case Map.get(refs, request_ref) do
      nil ->
        {:noreply, state}

      from ->
        GenServer.reply(from, {:error, :timeout})

        {:noreply,
         %{state | requests: Map.delete(requests, request_ref), refs: Map.delete(refs, request_ref)}}
    end
  end

  @doc false
  def handle_info(msg, %{conn: conn, requests: requests, refs: refs} = state) do
    case Peppermint.handle_message(conn, msg, requests) do
      {:ok, conn, {requests, responses}} ->
        Enum.each(responses, fn {request_ref, response} ->
          case Map.get(refs, request_ref) do
            nil -> :ok
            from -> GenServer.reply(from, {:ok, response})
          end
        end)

        {:noreply,
         %{state | conn: conn, requests: requests, refs: Map.drop(refs, Map.keys(responses))}}

      {:error, conn, reason, _responses} ->
        Enum.each(refs, fn {_, from} ->
          GenServer.reply(from, {:error, reason})
        end)

        {:noreply, %{state | conn: conn, requests: %{}, refs: %{}}}
    end
  end

  defp ensure_connection(%{conn: %{state: :open}} = state) do
    state
  end

  defp ensure_connection(%{url: url, options: options} = state) do
    {:ok, conn} = Peppermint.connect(url, options)
    %{state | conn: conn}
  end
end
