defmodule IntegrationTest do
  use ExUnit.Case
  doctest Peppermint

  test "get" do
    assert {:ok,
            %{
              body: nil,
              headers: _,
              status: 200
            }} = Peppermint.get("http://httpstat.us/200")
  end

  test "post" do
    assert {:ok,
            %{
              body: body,
              headers: _,
              status: 200
            }} = Peppermint.post("http://httpbin.org/post", params: %{test_arg: "2"})

    assert body =~ ~S["test_arg=2"]
  end

  test "post json" do
    {:ok, %{body: body}} =
      Peppermint.post("http://httpbin.org/post",
        headers: [{"Content-Type", "application/json"}],
        body: Jason.encode!(%{foo: "bar"})
      )

    assert %{"data" => "{\"foo\":\"bar\"}", "headers" => %{"Content-Type" => "application/json"}} =
             Jason.decode!(body)
  end

  test "options" do
    assert {:ok, %{headers: headers, status: 200}} = Peppermint.options("http://httpbin.org")
    assert %{"allow" => allow} = Map.new(headers)
    assert String.split(allow, ", ") |> Enum.sort() == ["GET", "HEAD", "OPTIONS"]
  end

  test "gzip" do
    assert {:ok, %{body: body}} = Peppermint.get("http://httpbin.org/gzip")
    assert body =~ ~S["gzipped": true]
  end

  test "deflate" do
    assert {:ok, %{body: body}} = Peppermint.get("http://httpbin.org/deflate")
    assert body =~ ~S["deflated": true]
  end

  test "custom headers" do
    assert {:ok, %{body: body}} =
             Peppermint.get("http://httpbin.org/headers", headers: [{"x-test-header", "123"}])

    assert body =~ ~S["X-Test-Header": "123"]
  end

  test "query as params" do
    assert {:ok, %{body: body}} =
             Peppermint.get("http://httpbin.org/get", params: %{test_arg: "1"})

    assert body =~ ~S["test_arg": "1"]
  end

  test "push promise is not supported" do
    assert_raise RuntimeError, fn -> Peppermint.get("https://http2.golang.org/serverpush") end
  end

  test "receive timeout" do
    assert {:error, :receive_timeout} =
             Peppermint.get("http://httpstat.us/200?sleep=100", receive_timeout: 50)
  end

  test "connect timeout" do
    assert {:error, %Mint.TransportError{reason: :timeout}} ==
             Peppermint.get("http://www.google.com:81", transport_opts: [timeout: 50])
  end
end
