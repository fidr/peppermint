defmodule Peppermint do
  require Mint.HTTP

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

  @doc section: :base_request
  def request(method, url, options \\ []) do
    uri = URI.parse(url)

    with {:ok, conn} <- connect(uri, options) do
      case request(conn, method, path(uri, method, options), options) do
        {:ok, conn, response} ->
          Mint.HTTP.close(conn)
          {:ok, response}

        {:error, conn, reason} ->
          Mint.HTTP.close(conn)
          {:error, reason}
      end
    end
  end

  @doc section: :reuse
  def connect(url, options) when is_binary(url) do
    connect(URI.parse(url), options)
  end

  @doc section: :reuse
  def connect(%URI{} = uri, options) do
    connect(scheme(uri.scheme), uri.host, uri.port, options)
  end

  @doc section: :reuse
  def connect(scheme, host, port, options) do
    Mint.HTTP.connect(scheme, host, port, options)
  end

  @doc section: :reuse
  def close(conn) do
    Mint.HTTP.close(conn)
  end

  @doc section: :reuse
  def request(conn, method, path, options) do
    headers = Keyword.get(options, :headers, [])
    body = body(method, options)

    case Mint.HTTP.request(conn, method(method), path, headers, body) do
      {:ok, conn, request_ref} ->
        receive_response(conn, request_ref, options) |> maybe_decompress(options)

      {:error, conn, reason} ->
        {:error, conn, reason}
    end
  end


  @doc false
  def receive_response(conn, request_ref, options, acc \\ new_acc()) do
    timeout = Keyword.get(options, :receive_timeout, 5_000)

    receive do
      message when Mint.HTTP.is_connection_message(conn, message) ->
        handle_message(conn, request_ref, message, options, acc)
    after
      timeout -> {:error, conn, :receive_timeout}
    end
  end

  @doc false
  def handle_message(conn, request_ref, message, options, acc) do
    case Mint.HTTP.stream(conn, message) do
      {:ok, conn, responses} ->
        case reduce_responses(conn, request_ref, responses, acc) do
          {:cont, conn, acc} -> receive_response(conn, request_ref, options, acc)
          {:ok, conn, acc} -> {:ok, conn, acc}
        end

      :unknown ->
        receive_response(conn, request_ref, options, acc)
    end
  end

  @doc false
  def reduce_responses(conn, request_ref, responses, acc) do
    Enum.reduce(responses, {:cont, conn, acc}, fn response, {action, conn, acc} ->
      case response do
        {:status, ^request_ref, status_code} ->
          {action, conn, Map.put(acc, :status, status_code)}

        {:headers, ^request_ref, headers} ->
          {action, conn, Map.update(acc, :headers, headers, fn h -> h ++ headers end)}

        {:data, ^request_ref, binary} ->
          {action, conn, Map.update(acc, :body, [binary], fn data -> [binary | data] end)}

        {:error, ^request_ref, reason} ->
          {action, conn, Map.put(acc, :error, reason)}

        {:pong, ^request_ref} ->
          {action, conn, acc}

        {:push_promise, ^request_ref, _promised_request_ref, _promised_headers} ->
          raise("push promise is not supported")

        {:done, ^request_ref} ->
          response = Map.update(acc, :body, nil, fn body -> Enum.join(Enum.reverse(body)) end)
          {:ok, conn, response}
      end
    end)
  end

  @doc false
  def maybe_decompress({:ok, conn, response}, options) do
    case Keyword.get(options, :raw) do
      true ->
        {:ok, conn, response}

      _ ->
        case Enum.find(response.headers, fn {k, _v} ->
               k == "content-encoding"
             end) do
          {"content-encoding", gzip} when gzip in ["gzip", "x-gzip"] ->
            {:ok, conn, %{response | body: :zlib.gunzip(response.body)}}

          {"content-encoding", "deflate"} ->
            {:ok, conn, %{response | body: :zlib.uncompress(response.body)}}

          _ ->
            {:ok, conn, response}
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
  def body(method, options) do
    cond do
      Keyword.get(options, :body) -> options[:body]
      method == :get -> nil
      Keyword.get(options, :params) -> URI.encode_query(options[:params])
      true -> nil
    end
  end

  @doc false
  def path(%{path: path, query: query}, :get, options) do
    query =
      (query || "")
      |> URI.decode_query()
      |> Map.merge(Keyword.get(options, :params, %{}))
      |> URI.encode_query()

    maybe_add_query(path, query)
  end

  @doc false
  def path(%{path: path, query: query}, _method, _options) do
    maybe_add_query(path, query)
  end

  @doc false
  def maybe_add_query(nil, query), do: maybe_add_query("/", query)
  def maybe_add_query("", query), do: maybe_add_query("/", query)
  def maybe_add_query(path, nil), do: path
  def maybe_add_query(path, ""), do: path
  def maybe_add_query(path, query), do: "#{path}?#{query}"

  defp new_acc() do
    %{status: nil, headers: []}
  end
end
