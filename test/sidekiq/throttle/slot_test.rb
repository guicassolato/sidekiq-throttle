require 'test_helper'

class Sidekiq::Throttle::SlotTest < ActiveSupport::TestCase
  Slot = Sidekiq::Throttle::Slot

  def setup
    options = { concurrency: 1, duration: 30.seconds }
    @slot = Slot.new('my-prefix', options)
  end

  test 'it has a prefix' do
    assert_equal 'my-prefix', @slot.prefix
  end

  test 'it has options' do
    options = { concurrency: 1, duration: 30.seconds }
    assert_equal options, @slot.options
  end

  test 'acquires slot or raise' do
    Timecop.freeze do
      assert @slot.acquire!
      assert_raise(Sidekiq::Throttle::OutOfSlotsError) { @slot.acquire! }
    end
  end

  test 'can acquire quietly' do
    Timecop.freeze do
      assert @slot.acquire
      assert_nothing_raised { @slot.acquire }
      refute @slot.acquire
    end
  end

  test 'multiple slots' do
    Timecop.freeze do
      options = { concurrency: 3, duration: 30.seconds }
      assert Slot.acquire('multiple', options)
      assert Slot.acquire('multiple', options)
      assert Slot.acquire('multiple', options)
      refute Slot.acquire('multiple', options)
    end
  end

  test 'out of slots with multiple slots' do
    Timecop.freeze do
      options = { concurrency: 3 }
      assert Slot.acquire('multiple', options)
      assert Slot.acquire('multiple', options)
      assert Slot.acquire('multiple', options)

      refute Slot.acquire('multiple', options)
      assert_raise(Sidekiq::Throttle::OutOfSlotsError) { Slot.acquire!('multiple', options) }
    end
  end

  test 'same slot is not taken more than once' do
    Timecop.freeze do
      slot1 = Slot.new('my-throttle', concurrency: 2)
      slot2 = Slot.new('my-throttle', concurrency: 2)
      slot1.acquire!
      3.times do
        slot2.acquire!
        assert_not_equal slot1.key, slot2.key
        slot2.release_now!
      end
    end
  end

  test 'scoped by prefix' do
    Timecop.freeze do
      options = { concurrency: 2 }
      assert Slot.acquire('multiple-1', options)
      assert Slot.acquire('multiple-1', options)
      refute Slot.acquire('multiple-1', options)
      assert Slot.acquire('multiple-2', options)
      assert Slot.acquire('multiple-2', options)
      assert Slot.acquire('multiple-3', options)
    end
  end

  test 'releases immediately' do
    Timecop.freeze do
      @slot.acquire!
      @slot.release_now!
      refute Slot.redis.get(@slot.key)
    end
  end

  test 'releases after ttl' do
    Timecop.freeze do
      @slot.acquire!
      @slot.stubs(ttl: 30)
      @slot.release!
      assert Slot.redis.get(@slot.key)
      Timecop.freeze(29.seconds.from_now) do
        assert Slot.redis.get(@slot.key)
        Timecop.freeze(1.seconds.from_now) do
          refute Slot.redis.get(@slot.key)
        end
      end
    end
  end

  test 'release is indempotent' do
    Timecop.freeze do
      @slot.acquire!
      assert @slot.release_now!
      assert @slot.release
      assert @slot.release
    end
  end

  test 'expire_in' do
    Slot.redis.expects(:expire)
    @slot.send(:expire_in, 10.seconds)

    Slot.redis.expects(:del)
    @slot.send(:expire_in, 0.seconds)
  end

  test 'acquired_at' do
    Timecop.freeze do
      @slot.acquire!
      assert_equal Time.now.to_i, @slot.acquired_at
    end
  end

  test 'executing_for' do
    Timecop.freeze do
      @slot.acquire!
      Timecop.freeze(10.seconds.from_now) do
        assert_equal 10, @slot.executing_for
      end
    end
  end

  test 'ttl' do
    Timecop.freeze do
      @slot.acquire!
      Timecop.freeze(20.seconds.from_now) do
        assert_equal 10.seconds, @slot.ttl

        Timecop.freeze(15.seconds.from_now) do
          assert_equal 0.seconds, @slot.ttl
        end
      end
    end
  end

  test 'live?' do
    Timecop.freeze do
      refute @slot.live?
      @slot.acquire!
      assert @slot.live?
      @slot.release_now!
      refute @slot.live?
    end
  end

  test 'expired?' do
    Timecop.freeze do
      assert @slot.expired?
      @slot.acquire!
      refute @slot.expired?
      @slot.release_now!
      assert @slot.expired?
    end
  end
end
