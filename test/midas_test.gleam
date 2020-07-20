import gleam/io
import gleam/uri
import midas/lean
import process/process
import gleam/http.{Get, Request, Response}
import midas/net/tcp
import midas/net/http as net_http
import gleam/should

pub external fn unsafe_receive(process.Wait) -> Result(m, Nil) =
  "process_native" "do_receive"

fn handle_request(request) {
  let body = http.get_body(request)
  case http.path_segments(request) {
    ["echo"] -> {
      let Ok(content_type) = http.get_header(request, "content-type")

      http.response(200)
      |> http.set_header("content-type", content_type)
      |> http.set_body(body)
    }
  }
}

pub fn echo_body_test() {
  assert Ok(listen_socket) = net_http.listen(0)
  let Ok(port) = net_http.port(listen_socket)
  let Ok(socket) = tcp.connect("localhost", port)

  let test = process.unsafe_self()
  // The runner exits normally when the supervisor is killed
  let runner = process.spawn_link(
    fn(receive) {
      process.process_flag(process.TrapExit(True))
      // For some reason the first acceptor is taken up with a slow connection
      let endpoint_pid = lean.spawn_link(
        handle_request,
        listen_socket,
        [lean.MaxConcurrency(2)],
      )
      process.send(test, endpoint_pid)
      let Ok(_) = receive(process.Infinity)
      Nil
    },
  )
  assert Ok(endpoint_pid) = unsafe_receive(process.Milliseconds(1000))

  let Ok(socket) = tcp.connect("localhost", port)
  let message = "GET /echo HTTP/1.1\r\nhost: midas.test\r\ncontent-length: 14\r\ncontent-type: text/unusual\r\n\r\nHello, Server!"
  let Ok(_) = tcp.send(socket, message)
  let Ok(response) = tcp.read_blob(socket, 0, 1000)
  should.equal(
    response,
    "HTTP/1.1 200 \r\nconnection: close\r\ncontent-type: text/unusual\r\n\r\nHello, Server!",
  )

  let Ok(socket) = tcp.connect("localhost", port)
  let message = "GET /echo HTTP/1.1\r\nhost: midas.test\r\nconnection: close\r\nhost: midas.test\r\ncontent-type: text/unusual\r\n\r\n"
  let Ok(_) = tcp.send(socket, message)
  let Ok(port) = net_http.port(listen_socket)
  let Ok(response) = tcp.read_blob(socket, 0, 100)
  should.equal(
    response,
    "HTTP/1.1 200 \r\nconnection: close\r\ncontent-type: text/unusual\r\n\r\n",
  )
  process.kill(endpoint_pid)
}
