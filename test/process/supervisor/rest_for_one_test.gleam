import gleam/option.{None, Some}
import process/process
import process/process.{
  BarePid, ExitReason, Flush, From, Infinity, Milliseconds, Normal, Pid, Ref,
  Timeout, TrapExit, Wait
}
import process/supervisor/rest_for_one
import gleam/should

pub external fn unsafe_receive(Wait) -> Result(m, Nil) =
  "process_native" "do_receive"

pub fn start_up_order_test() {
  let test = process.unsafe_self()
  rest_for_one.spawn_link(
    fn() {
      rest_for_one.Two(
        fn() {
          process.spawn_link(
            fn(receive) {
              process.send(test, process.self(receive))
              let _ = receive(Infinity)
              Nil
            },
          )
        },
        fn(first) {
          process.spawn_link(
            fn(receive) {
              process.send(test, first)
              process.send(test, process.self(receive))
              let _ = receive(Infinity)
              Nil
            },
          )
        },
      )
    },
  )

  let Ok(child1_from_self) = unsafe_receive(Milliseconds(100))
  let Ok(child1_from_child2) = unsafe_receive(Milliseconds(100))
  should.equal(child1_from_self, child1_from_child2)
  let Ok(child2_from_self) = unsafe_receive(Milliseconds(100))
  should.not_equal(child1_from_self, child2_from_self)

  // Everything is permanent so a Process exiting normally is restarted
  process.send(child2_from_self, Nil)
  let Ok(child1_from_child2_again) = unsafe_receive(Milliseconds(100))
  let Ok(child2_from_self_again) = unsafe_receive(Milliseconds(100))
  should.equal(child1_from_self, child1_from_child2_again)
  should.not_equal(child2_from_self, child2_from_self_again)

  // Restarts from kill as well as normal exit
  process.kill(child1_from_self)
  let Ok(child1_from_self_again) = unsafe_receive(Milliseconds(100))
  let Ok(child1_from_child2_again) = unsafe_receive(Milliseconds(100))
  should.equal(child1_from_self_again, child1_from_child2_again)
  let Ok(child2_from_self_again) = unsafe_receive(Milliseconds(100))
  should.not_equal(child1_from_self_again, child2_from_self_again)

  should.not_equal(child1_from_self, child1_from_self_again)
  should.not_equal(child2_from_self, child2_from_self_again)
}
// process.shutdown(sup)
// Leave the supervisor running. Stopping it if cancels further tests
// Related process exited with reason: xxx  (related process being the supervisor)
