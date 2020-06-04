defmodule HTTP1Test do
  use ExUnit.Case

  setup do
    {:ok, port, server_ref} = HTTP1.TestServer.start()
    [host: "http://localhost:#{port}", server_ref: server_ref]
  end

  test "simple request", %{host: host, server_ref: server_ref} do
    parent = self()
    spawn(fn -> send(parent, {:response, Peppermint.get("#{host}/")}) end)

    # server
    assert_receive {^server_ref, server_socket}
    assert_receive {:tcp, ^server_socket, data}
    assert data =~ "GET / HTTP/1.1\r\n"
    :ok = :gen_tcp.send(server_socket, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    assert_receive {:tcp_closed, ^server_socket}

    # response
    assert_receive {:response,
                    {:ok,
                     %Peppermint.Response{
                       body: nil,
                       headers: [{"content-length", "0"}],
                       status: 200
                     }}}
  end

  test "handle tcp closed", %{host: host, server_ref: server_ref} do
    parent = self()
    spawn(fn -> send(parent, {:response, Peppermint.get("#{host}/")}) end)

    assert_receive {^server_ref, server_socket}
    assert_receive {:tcp, ^server_socket, data}
    assert data =~ "GET / HTTP/1.1\r\n"
    :gen_tcp.shutdown(server_socket, :read_write)
    assert_receive {:tcp_closed, ^server_socket}

    assert_receive {:response, {:error, %Mint.TransportError{reason: :closed}}}
  end

  test "skips unknown messages", %{host: host, server_ref: server_ref} do
    parent = self()

    requester =
      spawn(fn ->
        send(parent, {:response, Peppermint.get("#{host}/")})

        receive do
          :some_message -> send(parent, {:received, :some_message})
        end
      end)

    assert_receive {^server_ref, server_socket}
    assert_receive {:tcp, ^server_socket, data}
    assert data =~ "GET / HTTP/1.1\r\n"
    send(requester, :some_message)
    :ok = :gen_tcp.send(server_socket, "HTTP/1.1 200\r\nContent-Length: 4\r\n\r\ntest")
    assert_receive {:tcp_closed, ^server_socket}

    assert_receive {:response,
                    {:ok,
                     %Peppermint.Response{
                       body: "test",
                       headers: [{"content-length", "4"}],
                       status: 200
                     }}}

    assert_receive {:received, :some_message}
  end

  test "async requests with single connection", %{host: host, server_ref: server_ref} do
    {:ok, conn} = Peppermint.Connection.open(host)
    assert_receive {^server_ref, server_socket}

    requests = [
        Task.async(fn -> Peppermint.Connection.request(conn, :get, "/a") end),
        Task.async(fn -> Peppermint.Connection.request(conn, :get, "/b") end),
        Task.async(fn -> Peppermint.Connection.request(conn, :get, "/c") end),
        Task.async(fn -> Peppermint.Connection.request(conn, :get, "/d") end)
      ]

    server_handle_requests(server_socket, ["response a", "response b", "response c", "response d"])

    responses = Enum.map(requests, &Task.await/1) |> Enum.sort()

    assert responses == [
      {:ok,
       %Peppermint.Response{
         body: "response a",
         headers: [{"content-length", "10"}],
         status: 200
       }},
      {:ok,
       %Peppermint.Response{
         body: "response b",
         headers: [{"content-length", "10"}],
         status: 200
       }},
      {:ok,
       %Peppermint.Response{
         body: "response c",
         headers: [{"content-length", "10"}],
         status: 200
       }},
      {:ok,
       %Peppermint.Response{
         body: "response d",
         headers: [{"content-length", "10"}],
         status: 200
       }}
    ]

    :ok = Peppermint.Connection.close(conn)
  end

  defp server_handle_requests(_, []), do: :ok

  defp server_handle_requests(server_socket, [body | rest]) do
    receive do
      {:tcp, ^server_socket, _data} ->
        :ok =
          :gen_tcp.send(
            server_socket,
            "HTTP/1.1 200\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
          )

        server_handle_requests(server_socket, rest)
    end
  end
end
