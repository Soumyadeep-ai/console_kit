# frozen_string_literal: true

# Runs two tenant switches on two threads in one fixed, latch-driven order:
#
#   thread A switches -> thread B switches -> thread B observes -> thread A observes
#
# so "did A keep its tenant while B moved?" is answered by construction rather
# than by luck. Every hand-off is a Queue pop, so there is no sleep and no race;
# both threads are joined before `run` returns.
class InterleavedSwitch
  attr_reader :threads

  def initialize(&observe)
    @observe = observe
    @b_may_switch = Queue.new
    @a_may_observe = Queue.new
    @readings = {}
    @threads = []
  end

  # `first` runs on thread A, `second` on thread B. Returns
  # { a: <observation>, b: <observation> }.
  def run(first, second)
    @threads = [spawn { thread_a(first) }, spawn { thread_b(second) }]
    @threads.each(&:join)
    @readings
  end

  private

  def spawn(&block)
    Thread.new do
      ConsoleKit::Output.silent = true
      block.call
    end
  end

  def thread_a(action)
    action.call
    @b_may_switch << :go
    @a_may_observe.pop
    @readings[:a] = @observe.call
  end

  def thread_b(action)
    @b_may_switch.pop
    action.call
    @readings[:b] = @observe.call
    @a_may_observe << :go
  end
end
