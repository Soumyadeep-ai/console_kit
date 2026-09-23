# frozen_string_literal: true

class InterleavedSwitch
  attr_reader :threads

  def initialize(&observe)
    @observe = observe
    @b_may_switch = Queue.new
    @a_may_observe = Queue.new
    @readings = {}
    @threads = []
  end

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
