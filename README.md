# Peppermint

Simple Elixir HTTP client build on [Mint](https://github.com/elixir-mint/mint). It supports both HTTP 1 and HTTP 2 requests.

Peppermint aims to provide a simple interface build on the modern low-level Mint library. It provides a process-less and pool-less architecture.

Currently peppermint requires elixir `~> 1.10`

## Installation

Add to your `mix.exs` and run `mix deps.get`:

```elixir
def deps do
  [
    {:peppermint, "~> 0.1.0"},
    {:castore, "~> 0.1.0"}
  ]
end
```

## Usage

### Examples

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

You can reuse your connection if need to do multiple requests to the same host. For more advanced usecases you should use Mint directly.

```elixir
{:ok, conn} = Peppermint.connect("http://httpbin.org", [])
{:ok, conn, response1} = Peppermint.request(conn, :get, "/get?foo=bar", [])
{:ok, conn, response2} = Peppermint.request(conn, :post, "/post", params: %{foo: "bar"})
{:ok, _conn} = Peppermint.close(conn)
```


## Acknowledgements

 - Check out [Mint](https://github.com/elixir-mint/mint) for more low-level and advanced usecases
 - Check out [Mojito](https://github.com/appcues/mojito) if you need connection pooling
