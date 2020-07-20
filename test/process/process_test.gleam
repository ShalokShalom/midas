import gleam/option.{None, Option, Some}
import process/process
import process/process.{
  BarePid, ExitReason, Flush, From, Gone, Infinity, Milliseconds, MonitorType,
  Normal, Pid, Process, Ref, Timeout, TrapExit, Wait
}
import gleam/should

pub external fn unsafe_receive(Wait) -> Result(m, Nil) =
  "process_native" "do_receive"

pub fn send_message_test() {
  let test = process.unsafe_self()

  let pid = process.spawn_link(
    fn(receive) {
      let r = receive(Milliseconds(100))
      process.send(test, r)
    },
  )

  process.send(pid, 5)
  should.equal(Ok(Ok(5)), unsafe_receive(Infinity))
}

pub fn receive_timeout_test() {
  let test = process.unsafe_self()

  process.spawn_link(
    fn(receive) {
      let r = receive(Milliseconds(100))
      process.send(test, r)
    },
  )

  should.equal(Error(Nil), unsafe_receive(Milliseconds(0)))
  should.equal(Ok(Error(Nil)), unsafe_receive(Infinity))
}

pub fn reference_to_self_test() {
  let test = process.unsafe_self()

  let pid = process.spawn_link(
    fn(receive) {
      process.send(test, process.self(receive))
      process.send(test, process.unsafe_self())
    },
  )

  should.equal(Ok(pid), unsafe_receive(Infinity))
  should.equal(Ok(pid), unsafe_receive(Infinity))
}

pub type Exit {
  Exit(BarePid, ExitReason)
}

pub fn kill_process_test() {
  let test = process.unsafe_self()

  process.spawn_link(
    fn(receive) {
      process.process_flag(TrapExit(True))

      let child = process.spawn_link(
        fn(r2) {
          let _ = r2(Infinity)
          Nil
        },
      )
      process.kill(child)
      let r = receive(Milliseconds(100))
      process.send(test, r)
    },
  )

  let Ok(response) = unsafe_receive(Infinity)
  let Ok(Exit(_down_pid, reason)) = response
  // Need to sort out kill and killed.
  // All other exit reasons are the same on both sides.
  should.equal(reason, process.Killed)
}

pub type Down {
  Down(Ref, MonitorType, BarePid, ExitReason)
}

pub fn monitor_test() {
  let pid = process.spawn_link(fn(_) { Nil })

  let monitor_reference = process.monitor(pid)
  let Ok(
    Down(down_reference, Process, down_pid, Normal),
  ) = unsafe_receive(Infinity)
  should.equal(monitor_reference, down_reference)
  should.equal(process.bare(pid), down_pid)
}

// Needs to start a process trapping exits
// pub fn monitor_shutdown_test() {
//     let pid = process.spawn_link(fn(_) { Shutdown })
//
//     let monitor_reference = process.monitor(Process, pid)
//     let Ok(Down(down_reference, Process, down_pid, Shutdown)) = unsafe_receive(Infinity)
//     should.equal(monitor_reference, down_reference)
//     should.equal(process.bare(pid), down_pid)
// }
pub fn demonitor_flush_test() {
  let pid = process.spawn_link(fn(_) { Nil })

  let monitor_reference = process.monitor(pid)
  let True = process.demonitor(monitor_reference, [Flush])
  let Error(Nil) = unsafe_receive(Milliseconds(100))
  Nil
}

type Ping(m) {
  Ping(From(m), m)
}

pub fn call_task_test() {
  let pid = process.spawn_link(
    fn(receive) {
      let Ok(Ping(from, value)) = receive(Infinity)
      process.reply(from, value)
    },
  )

  let reply = process.call(pid, Ping(_, 7), Milliseconds(100))
  should.equal(reply, Ok(7))
}

pub fn call_timeout_for_slow_process_test() {
  let pid = process.spawn_link(
    fn(receive) {
      let _ = receive(Infinity)
      // Receive twice because call sends message for first one
      let _ = receive(Infinity)
      Nil
    },
  )
  let reply = process.call(pid, Ping(_, 500), Milliseconds(100))

  should.equal(reply, Error(Timeout))
}

pub fn call_error_for_down_process_test() {
  let pid = process.spawn_link(fn(_) { Nil })
  let reply = process.call(pid, Ping(_, 500), Infinity)

  // Gone(ExitReason)/Slow
  should.equal(reply, Error(Gone))
}
