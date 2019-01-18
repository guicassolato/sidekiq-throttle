require 'test_helper'

class Sidekiq::ThrottleTest < ActiveSupport::TestCase
  worker_klass = Class.new do
    include Sidekiq::Throttle

    def self.get_sidekiq_options
      {}
    end
  end

  test 'it has a version number' do
    refute_nil ::Sidekiq::Throttle::VERSION
  end

  setup do
    @worker = worker_klass.new
  end

  test 'throttle options defaults' do
    options = @worker.send(:throttle_options)
    assert_equal 1, options[:concurrency]
    assert_equal 30, options[:duration]
    assert_equal :perform_async, options[:fallback_method]
  end

  test 'custom throttle options for any throttle' do
    worker_klass.stubs(get_sidekiq_options: { 'throttle' => { 'concurrency' => 2, 'duration' => 30.seconds } } )
    options = @worker.send(:throttle_options)
    assert_equal 2, options[:concurrency]
    assert_equal 30, options[:duration]
    assert_equal :perform_async, options[:fallback_method]
  end

  test 'custom throttle options for a given throttle' do
    all_throttles_options = { 'concurrency' => 10, 'fallback_method' => :custom_method }
    my_throttle_options = { 'concurrency' => 2, duration: 1.minute }
    worker_klass.stubs(get_sidekiq_options: { 'throttle' => { 'my-throttle' => my_throttle_options }.merge(all_throttles_options) } )

    options = @worker.send(:throttle_options_for, 'my-throttle')
    assert_equal 2, options[:concurrency]
    assert_equal 1.minute, options[:duration]
    assert_equal :custom_method, options[:fallback_method]

    options = @worker.send(:throttle_options_for, 'other-throttle')
    assert_equal 10, options[:concurrency]
    assert_equal 30.seconds, options[:duration] # default
    assert_equal :custom_method, options[:fallback_method]
  end

  test 'reenqueue with same args' do
    payload = ['a', 'b', 'c']
    worker_klass.expects(:perform_async).with(*payload)
    @worker.send(:reenqueue, *payload)
  end

  test 'custom reenqueue method' do
    worker_klass.stubs(get_sidekiq_options: { 'throttle' => { fallback_method: [:perform_in, 1.minute] } } )
    payload = [1, 2]
    worker_klass.expects(:perform_in).with(1.minute, *payload)
    @worker.send(:reenqueue, *payload)
  end

  Slot = Sidekiq::Throttle::Slot

  test 'acquires a slot' do
    throttle_name = 'my-throttle'
    slot = Slot.new(throttle_name)
    Slot.expects(:acquire).with(throttle_name, *any_parameters).returns(slot)
    slot.stubs(release: true)
    @worker.throttle(throttle_name)
  end

  test 'yields the block' do
    exception_klass = Class.new(StandardError)
    block = lambda { raise exception_klass }
    assert_raise(exception_klass) { @worker.throttle('my-throttle', &block) }
  end

  test 'slot is always released' do
    Timecop.freeze do
      throttle_name = 'my-throttle'
      slot = Slot.new(throttle_name)
      Slot.expects(:acquire).twice.with(throttle_name, *any_parameters).returns(slot)
      slot.expects(:release).twice

      @worker.throttle(throttle_name)

      exception_klass = Class.new(StandardError)
      block = lambda { raise exception_klass }
      assert_raise(exception_klass) { @worker.throttle(throttle_name, &block) }
    end
  end

  module PerformWithFiber
    def perform(job_arg)
      throttle('my-throttle', job_arg) do
        Fiber.yield
      end
    end
  end

  test 'ensures limited number of slots are taken' do
    worker_klass.stubs(get_sidekiq_options: { 'throttle' => { 'concurrency' => 2, 'duration' => 30.seconds } } )
    worker_klass.prepend(PerformWithFiber)

    Slot.any_instance.stubs(:release!).twice.returns(false)

    Timecop.freeze do
      f1 = Fiber.new { worker_klass.new.perform 1 }
      f2 = Fiber.new { worker_klass.new.perform 2 }
      f3 = Fiber.new { worker_klass.new.perform 3 }

      worker_klass.expects(:perform_async).with(3)

      f1.resume
      f2.resume
      f3.resume

      f1.resume
      f2.resume
      assert_raises(FiberError) { f3.resume }
    end
  end
end
