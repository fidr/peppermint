# Peppermint

Simple Elixir HTTP client build on [Mint](https://github.com/elixir-mint/mint). It supports both HTTP/1 and HTTP/2 requests.

Peppermint aims to provide a simple interface build on the modern low-level Mint library. It provides a pool-less architecture, but it can be used to build your own connection pools easily.

Currently peppermint requires elixir `~> 1.10`

## Installation

Add to your `mix.exs` and run `mix deps.get`:

```elixir
def deps do
  [
    {:peppermint, "~> 0.2.0"},
    {:castore, "~> 0.1.0"}
  ]
end
```

## Usage

### Examples

Fire a one-off request. Connects to the host, executes the request and disconnects.

#### GET
```elixir
{:ok, %{status: 200, headers: headers, body: body}} =
  Peppermint.get("http://httpbin.org/get?foo=bar")
```

#### GET with params (sent as query in the path)
```elixir
{:ok, %{status: 200, headers: headers, body: body}} =
  Peppermint.get("http://httpbin.org/get", params: %{foo: "bar"})
```

#### POST with params
```elixir
{:ok, %{status: 200, headers: headers, body: body}} =
  Peppermint.post("http://httpbin.org/post", params: %{foo: "bar"})
```

#### POST JSON
```elixir
{:ok, %{status: 200, headers: headers, body: body}} =
  Peppermint.post("http://httpbin.org/post",
    headers: [{"Content-Type", "application/json"}],
    body: Jason.encode!(%{foo: "bar"})
  )
```

#### Other methods

`put`, `patch`, `delete`, `head`, `options` and `trace`

#### Timeouts

 - `transport_options`: [See mint docs](https://hexdocs.pm/mint/Mint.HTTP.html#connect/4-transport-options) - The `timeout` here specifies the connect timeout (defaults to `30_000`)
 - `receive_timeout` - Trigger timeout if no data received for x ms (defaults to `5_000`)

```elixir
Peppermint.get("http://httpbin.org/get",
  receive_timeout: 1_000,
  transport_options: [timeout: 5_000]
)
```

#### Reuse connection

To reuse a connection, the `Peppermint.Connection` provides a simple GenServer to handle a connection and
simultanious requests over HTTP/2 (multiplexing) or sequentially over HTTP/1:

```elixir
{:ok, conn} = Peppermint.Connection.open("http://httpbin.org")
{:ok, response} = Peppermint.Connection.request(conn, :get, "/get?foo=bar")
{:ok, response} = Peppermint.Connection.request(conn, :post, "/post", params: %{foo: "bar"})
:ok = Peppermint.Connection.close(conn)
```


## Acknowledgements

 - Check out [Mint](https://github.com/elixir-mint/mint) for more low-level and advanced usecases
 - Check out [Mojito](https://github.com/appcues/mojito) if you need connection pooling
