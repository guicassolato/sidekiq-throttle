module Sidekiq
  module Throttle
    class OutOfSlotsError < StandardError; end
    class AlreadyExpiredError < StandardError; end

    class Slot
      class << self
        def redis
          Sidekiq.redis { |conn| conn }
        end

        def acquire!(prefix, options = {})
          slot = new(prefix, options)
          slot.acquire!
          slot
        end

        def acquire(prefix, options = {})
          acquire! prefix, options
        rescue OutOfSlotsError
          return nil
        end
      end

      def initialize(prefix, options = {})
        @prefix = prefix
        @options = options.symbolize_keys
      end

      attr_reader :prefix, :options, :key

      def acquire!
        (1..concurrency).to_a.shuffle.each do |attempt|
          @key = "#{prefix}-#{attempt}"
          # FIXME: add a default expire (slot timeout), just in case the user never calls #release!
          return true if redis.setnx(key, timestamp)
        end

        raise OutOfSlotsError
      end

      def acquire
        acquire!
      rescue OutOfSlotsError
        return false
      end

      def release!
        expire_in ttl
      end

      def release
        release!
      rescue AlreadyExpiredError
        expired?
      end

      def release_now!
        expire_in 0
      end

      def release_now
        release_now!
      rescue AlreadyExpiredError
        expired?
      end

      def acquired_at
        value = redis.get(key) or raise AlreadyExpiredError
        value.to_i
      end

      # in seconds
      def executing_for
        timestamp - acquired_at
      end

      def ttl
        [duration - executing_for, 0].max
      end

      def duration
        options.fetch(:duration, 30.seconds)
      end

      def live?
        redis.exists key
      end

      def expired?
        !live?
      end

      protected

      def redis
        self.class.redis
      end

      def timestamp
        Time.now.to_i
      end

      def concurrency
        options.fetch(:concurrency, 1)
      end

      def expire_in(seconds)
        if seconds.positive?
          redis.expire key, seconds
        else
          redis.del key
        end
      end
    end
  end
end
