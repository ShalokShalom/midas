import gleam/atom.{Atom}
import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/list
import process/process
import process/process.{
  BarePid, ExitReason, From, Infinity, Milliseconds, Pid, Wait
}
import process/supervisor/set_supervisor
import gleam/should

pub external fn unsafe_receive(Wait) -> Result(m, Nil) =
  "process_native" "do_receive"

type Message {
  Expected
  Crash
}

// start child fn takes test pid
fn start_child(arg) {
  process.spawn_link(
    fn(receive) {
      let tuple(pid, id) = arg
      process.send(pid, id)
      assert Ok(Expected) = receive(Infinity)
      Nil
    },
  )
}

// Have this in process would allow unsafereceive easier BUT harder to work with in mapping function
type Down {
  Down(
    ref: process.Ref,
    monitor_type: Atom,
    pid: process.BarePid,
    reason: Dynamic,
  )
}

type Exit {
  Exit(pid: process.BarePid, reason: Dynamic)
}

pub fn temporary_children_test() {
  let test = process.unsafe_self()
  let runner = process.spawn_link(
    fn(receive) {
      process.process_flag(process.TrapExit(True))
      let supervisor = set_supervisor.spawn_link(
        start_child,
        set_supervisor.Temporary,
      )
      process.send(test, supervisor)
      let Ok(_) = receive(Infinity)
      Nil
    },
  )
  assert Ok(supervisor) = unsafe_receive(Milliseconds(100))

  should.equal(Ok([]), set_supervisor.which_children(supervisor))
  let Ok(c1) = set_supervisor.start_child(supervisor, tuple(test, 1))
  assert Ok(1) = unsafe_receive(Milliseconds(100))
  let Ok(c2) = set_supervisor.start_child(supervisor, tuple(test, 2))
  assert Ok(2) = unsafe_receive(Milliseconds(100))
  let Ok(c3) = set_supervisor.start_child(supervisor, tuple(test, 3))
  assert Ok(3) = unsafe_receive(Milliseconds(100))

  set_supervisor.which_children(supervisor)
  |> should.equal(Ok([c1, c2, c3]))

  let r1 = process.monitor(c1)
  process.send(c1, Expected)
  assert Ok(
    Down(ref: ref, pid: pid, reason: reason, ..),
  ) = unsafe_receive(Milliseconds(100))
  should.equal(ref, r1)
  should.equal(pid, process.bare(c1))
  should.equal(reason, dynamic.from(atom.create_from_string("normal")))
  process.send(c2, Crash)
  let r2 = process.monitor(c2)
  assert Ok(
    Down(ref: ref, pid: pid, reason: reason, ..),
  ) = unsafe_receive(Milliseconds(100))
  should.equal(ref, r2)
  should.equal(pid, process.bare(c2))
  should.equal(
    dynamic.element(reason, 0),
    Ok(dynamic.from(tuple(atom.create_from_string("badmatch"), Ok(Crash)))),
  )

  should.equal(Ok([c3]), set_supervisor.which_children(supervisor))

  // Stop the runner
  let r_sup = process.monitor(supervisor)
  let r3 = process.monitor(c3)
  // If had channels could listen for individual monitor
  // process.send(runner, Expected)
  process.kill(supervisor)
  assert Ok(
    Down(ref: ref, pid: pid, reason: reason, ..),
  ) = unsafe_receive(Milliseconds(100))
  should.equal(ref, r_sup)
  should.equal(pid, process.bare(supervisor))
  // should.equal(reason, dynamic.from(atom.create_from_string("killed")))
  assert Ok(
    Down(ref: ref, pid: pid, reason: reason, ..),
  ) = unsafe_receive(Milliseconds(100))
  should.equal(ref, r3)
  should.equal(pid, process.bare(c3))
  should.equal(reason, dynamic.from(atom.create_from_string("killed")))
}

pub fn permanent_children_test() {
  let test = process.unsafe_self()
  let runner = process.spawn_link(
    fn(receive) {
      process.process_flag(process.TrapExit(True))
      let supervisor = set_supervisor.spawn_link(
        start_child,
        set_supervisor.Permanent,
      )
      process.send(test, supervisor)
      let Ok(_) = receive(Infinity)
      Nil
    },
  )
  assert Ok(supervisor) = unsafe_receive(Milliseconds(100))

  should.equal(Ok([]), set_supervisor.which_children(supervisor))
  let Ok(c1) = set_supervisor.start_child(supervisor, tuple(test, 1))
  assert Ok(1) = unsafe_receive(Milliseconds(100))
  let Ok(c2) = set_supervisor.start_child(supervisor, tuple(test, 2))
  assert Ok(2) = unsafe_receive(Milliseconds(100))

  set_supervisor.which_children(supervisor)
  |> should.equal(Ok([c1, c2]))

  let r1 = process.monitor(c1)
  process.send(c1, Expected)
  assert Ok(
    Down(ref: ref, pid: pid, reason: reason, ..),
  ) = unsafe_receive(Milliseconds(100))
  should.equal(ref, r1)
  should.equal(pid, process.bare(c1))
  should.equal(reason, dynamic.from(atom.create_from_string("normal")))

  assert Ok(children) = set_supervisor.which_children(supervisor)
  should.equal(list.length(children), 2)
  assert Ok(1) = unsafe_receive(Milliseconds(100))

  // which children
  let r2 = process.monitor(c2)
  process.send(c2, Crash)
  assert Ok(
    Down(ref: ref, pid: pid, reason: reason, ..),
  ) = unsafe_receive(Milliseconds(100))
  should.equal(ref, r2)
  should.equal(pid, process.bare(c2))
  should.equal(
    dynamic.element(reason, 0),
    Ok(dynamic.from(tuple(atom.create_from_string("badmatch"), Ok(Crash)))),
  )
  assert Ok(children) = set_supervisor.which_children(supervisor)
  should.equal(list.length(children), 2)
  assert Ok(2) = unsafe_receive(Milliseconds(100))
  process.kill(supervisor)
}
