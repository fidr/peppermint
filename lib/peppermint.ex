defmodule Peppermint do
  require Mint.HTTP
  require Logger

  @moduledoc """
  Processless HTTP functions build on Mint.

  Examples:

      {:ok, response} = Peppermint.get("http://httpbin.org/")
      {:ok, response} = Peppermint.post("http://httpbin.org/post", params: %{foo: "bar"})
  """

  @type request_error :: {:error, Mint.Types.error() | :receive_timeout}

  @spec get(String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error
  @spec post(String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error
  @spec put(String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error
  @spec patch(String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error
  @spec delete(String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error
  @spec head(String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error
  @spec options(String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error
  @spec trace(String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error

  @doc section: :request_helper
  def get(url, options \\ []), do: request(:get, url, options)

  @doc section: :request_helper
  def post(url, options \\ []), do: request(:post, url, options)

  @doc section: :request_helper
  def put(url, options \\ []), do: request(:put, url, options)

  @doc section: :request_helper
  def patch(url, options \\ []), do: request(:patch, url, options)

  @doc section: :request_helper
  def delete(url, options \\ []), do: request(:delete, url, options)

  @doc section: :request_helper
  def head(url, options \\ []), do: request(:head, url, options)

  @doc section: :request_helper
  def options(url, options \\ []), do: request(:options, url, options)

  @doc section: :request_helper
  def trace(url, options \\ []), do: request(:trace, url, options)

  @doc """
  Connect to the host, execute a request and disconnect.
  """
  @doc section: :base_request
  @spec request(atom, String.t(), keyword) :: {:ok, Peppermint.Response.t()} | request_error
  def request(method, url, options \\ []) do
    uri = URI.parse(url)

    with {:ok, conn} <- connect(uri, options),
         {:ok, conn, request_ref} <- execute(conn, method, path(uri, method, options), options),
         {:ok, conn, response} <- receive_response(conn, request_ref, options) do
      Mint.HTTP.close(conn)
      {:ok, maybe_decompress(response, options)}
    else
      {:error, conn, reason} ->
        Mint.HTTP.close(conn)
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec connect(String.t()) :: {:ok, Mint.HTTP.t()} | {:error, Mint.Types.error()}
  @spec connect(String.t(), keyword) :: {:ok, Mint.HTTP.t()} | {:error, Mint.Types.error()}
  @spec connect(URI.t(), keyword) :: {:ok, Mint.HTTP.t()} | {:error, Mint.Types.error()}
  @spec connect(Mint.Types.scheme(), String.t(), :inet.port_number(), keyword()) ::
          {:ok, Mint.HTTP.t()} | {:error, Mint.Types.error()}

  def connect(url, options \\ [])
  def connect(url, options) when is_binary(url), do: connect(URI.parse(url), options)
  def connect(%URI{} = uri, options), do: connect(scheme(uri.scheme), uri.host, uri.port, options)
  def connect(scheme, host, port, options), do: Mint.HTTP.connect(scheme, host, port, options)

  @spec close(Mint.HTTP.t()) :: {:ok, Mint.HTTP.t()}
  def close(conn), do: Mint.HTTP.close(conn)

  @doc """
  Execute a request on a (Mint) connection. Response messages will be sent to the caller process
  """
  @spec execute(Mint.HTTP.t(), atom, String.t(), keyword) ::
          {:ok, Mint.HTTP.t(), Mint.Types.request_ref()} | {:error, Mint.HTTP.t(), any}
  def execute(conn, method, path, options \\ []) do
    headers = Keyword.get(options, :headers, [])
    body = body(method, options)
    Mint.HTTP.request(conn, method(method), path, headers, body)
  end

  @doc """
  Receive the response of a single request_req
  """
  @spec receive_response(Mint.HTTP.t(), Mint.Types.request_ref(), keyword) ::
          {:ok, Mint.HTTP.t(), Peppermint.Response.t()} | {:error, Mint.HTTP.t(), any}
  def receive_response(conn, request_ref, options, acc \\ nil) do
    acc = acc || %{request_ref => %{}}
    timeout = Keyword.get(options, :receive_timeout, 5_000)

    receive do
      message when Mint.HTTP.is_connection_message(conn, message) ->
        case handle_message(conn, message, acc) do
          {:ok, conn, {_acc, %{^request_ref => result}}} ->
            case result do
              {:error, reason} ->
                {:error, conn, reason}

              response ->
                {:ok, conn, response}
            end

          {:ok, conn, {acc, _results}} ->
            receive_response(conn, request_ref, options, acc)

          {:error, conn, reason, _acc} ->
            {:error, conn, reason}

          {:unknown, conn, acc} ->
            receive_response(conn, request_ref, options, acc)
        end
    after
      timeout -> {:error, conn, :receive_timeout}
    end
  end

  @doc """
  Handle a Mint message. Requires a map as accumulator which contains the requested
  request_ref's as keys and maps as values. Returns both the accumulator and any done
  responses.HTTP

  Can be used in a receive loop or for example in a GenServer.

      {:ok, conn, request_ref} = Peppermint.request(conn, :get, "/")

      acc = %{request_ref => %{}}

  When receiving a message:

      case handle_message(conn, message, acc) do
        {:ok, conn, {acc, results}} ->
          # check if your request_ref is in the results

        {:error, conn, reason, results} ->
          # error in the connection, you'd probably want to abort here

        {:unknown, conn, acc} ->
          # unknown message, use `Mint.HTTP.is_connection_message` to guard this from hapening
      end

  """
  def handle_message(conn, message, acc) do
    case Mint.HTTP.stream(conn, message) do
      {:ok, conn, responses} ->
        {acc, results} = handle_responses(acc, responses)
        {:ok, conn, {acc, results}}

      {:error, conn, reason, responses} ->
        {_acc, results} = handle_responses(acc, responses)
        {:error, conn, reason, results}

      :unknown ->
        {:unknown, conn, acc}
    end
  end

  defp handle_responses(acc, responses) do
    Enum.reduce(responses, {acc, %{}}, fn response, {acc, results} ->
      {request_ref, response} = extract_request_ref(response)

      case Map.get(acc, request_ref) do
        nil ->
          {acc, results}

        request ->
          case handle_response(request, response) do
            {request, nil} ->
              {Map.put(acc, request_ref, request), results}

            {nil, result} ->
              {Map.delete(acc, request_ref), Map.put(results, request_ref, result)}
          end
      end
    end)
  end

  defp handle_response(request, msg) do
    case msg do
      {:status, status_code} ->
        {Map.put(request, :status, status_code), nil}

      {:headers, headers} ->
        {Map.update(request, :headers, headers, fn h -> h ++ headers end), nil}

      {:data, binary} ->
        {Map.update(request, :body, [binary], fn data -> [binary | data] end), nil}

      {:error, reason} ->
        {nil, {:error, reason}}

      :pong ->
        {request, nil}

      {:push_promise, _promised_request_ref, promised_headers} ->
        Logger.warn("Unsupported push promise with headers #{inspect(promised_headers)}")
        {request, nil}

      :done ->
        {nil, build_response(request)}

      other ->
        Logger.warn("Unsupported HTTP message #{inspect(other)}")
        {request, nil}
    end
  end

  defp extract_request_ref(response) do
    case response do
      {:status, request_ref, status_code} -> {request_ref, {:status, status_code}}
      {:headers, request_ref, status_code} -> {request_ref, {:headers, status_code}}
      {:data, request_ref, status_code} -> {request_ref, {:data, status_code}}
      {:error, request_ref, status_code} -> {request_ref, {:error, status_code}}
      {:push_promise, request_ref, ref, headers} -> {request_ref, {:push_promise, ref, headers}}
      {:pong, request_ref} -> {request_ref, :pong}
      {:done, request_ref} -> {request_ref, :done}
      other -> {nil, other}
    end
  end

  defp build_response(request) do
    request = Map.update(request, :body, nil, fn body -> Enum.join(Enum.reverse(body)) end)
    struct(Peppermint.Response, request)
  end

  @doc false
  def maybe_decompress(%{headers: headers, body: body} = response, options) do
    case Keyword.get(options, :raw) do
      true ->
        response

      _ ->
        case Enum.find(headers, fn {k, _v} -> k == "content-encoding" end) do
          {"content-encoding", gzip} when gzip in ["gzip", "x-gzip"] ->
            %{response | body: :zlib.gunzip(body)}

          {"content-encoding", "deflate"} ->
            %{response | body: :zlib.uncompress(body)}

          _ ->
            response
        end
    end
  end

  @doc false
  def maybe_decompress(response, _options) do
    response
  end

  @doc false
  def scheme("https"), do: :https
  def scheme("http"), do: :http

  @doc false
  def method(:get), do: "GET"
  def method(:put), do: "PUT"
  def method(:post), do: "POST"
  def method(:patch), do: "PATCH"
  def method(:head), do: "HEAD"
  def method(:delete), do: "DELETE"
  def method(:options), do: "OPTIONS"
  def method(:connect), do: "CONNECT"
  def method(:trace), do: "TRACE"
  def method(method) when is_binary(method), do: method

  @doc false
  defp body(method, options) do
    cond do
      Keyword.get(options, :body) -> options[:body]
      method == :get -> nil
      Keyword.get(options, :params) -> URI.encode_query(options[:params])
      true -> nil
    end
  end

  @doc false
  defp path(%{path: path, query: query}, :get, options) do
    query =
      (query || "")
      |> URI.decode_query()
      |> Map.merge(Keyword.get(options, :params, %{}))
      |> URI.encode_query()

    maybe_add_query(path, query)
  end

  @doc false
  defp path(%{path: path, query: query}, _method, _options) do
    maybe_add_query(path, query)
  end

  @doc false
  defp maybe_add_query(nil, query), do: maybe_add_query("/", query)
  defp maybe_add_query("", query), do: maybe_add_query("/", query)
  defp maybe_add_query(path, nil), do: path
  defp maybe_add_query(path, ""), do: path
  defp maybe_add_query(path, query), do: "#{path}?#{query}"
end
