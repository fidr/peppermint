defmodule HTTP2Test do
  use ExUnit.Case
  import Mint.HTTP2.Frame

  import HTTP2.TestServer, only: [recv_next_frames: 2]

  @default_opts transport_opts: [verify: :verify_none]

  setup do
    {:ok, port, server_ref} = HTTP2.TestServer.start()
    [host: "https://localhost:#{port}", server_ref: server_ref]
  end

  test "simple request", %{host: host, server_ref: server_ref} do
    parent = self()
    spawn(fn -> send(parent, {:response, Peppermint.get("#{host}/", @default_opts)}) end)

    assert_receive {^server_ref, server}
    assert [headers(stream_id: stream_id)] = recv_next_frames(server, 1)

    send_frames(server, [
      {:headers, stream_id, [{":status", "200"}], [:end_headers]},
      {:data, stream_id, "hello", [:end_stream]}
    ])

    assert [window_update(), window_update(), rst_stream()] = recv_next_frames(server, 3)

    assert_receive {:response, {:ok, %Peppermint.Response{body: "hello", headers: [], status: 200}}}
  end

  test "error in response to request", %{host: host, server_ref: server_ref} do
    parent = self()
    spawn(fn -> send(parent, {:response, Peppermint.get("#{host}/", @default_opts)}) end)

    assert_receive {^server_ref, server}
    assert [headers(stream_id: stream_id)] = recv_next_frames(server, 1)

    send_frames(server, [
      {:headers, stream_id, [{":status", "200"}], [:end_headers]},
      rst_stream(stream_id: stream_id, error_code: :protocol_error)
    ])

    assert [goaway()] = recv_next_frames(server, 1)
    assert_receive {:ssl_closed, _}

    assert_receive {:response,
                    {:error,
                     %Mint.HTTPError{
                       __exception__: true,
                       module: Mint.HTTP2,
                       reason: {:server_closed_request, :protocol_error}
                     }}}
  end

  defp send_frames(server, frames) do
    {server, data} = HTTP2.TestServer.encode_frames(server, frames)
    :ssl.send(server.socket, data)
    server
  end
end
