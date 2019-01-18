require 'sidekiq/throttle/version'
require 'sidekiq/throttle/slot'

require 'active_support'
require 'active_support/core_ext'

module Sidekiq
  module Throttle
    def throttle(name, *job_args)
      return reenqueue(*job_args) unless slot = acquire_throttle_slot(name)

      begin
        yield if block_given?
      ensure
        slot.release
      end
    end

    protected

    DEFAULT_THROTTLE_OPTIONS = {
      number_of_slots: 1,
      duration: 30.seconds,
      fallback_method: :perform_async
    }
    private_constant :DEFAULT_THROTTLE_OPTIONS

    def throttle_options
      options = HashWithIndifferentAccess.new(self.class.get_sidekiq_options['throttle'] || {})
      options.symbolize_keys.reverse_merge(DEFAULT_THROTTLE_OPTIONS)
    end

    def throttle_options_for(throttle_name)
      options = throttle_options.fetch(throttle_name.to_sym, {})
      throttle_options.slice(*DEFAULT_THROTTLE_OPTIONS.keys).merge(options.symbolize_keys)
    end

    def acquire_throttle_slot(throttle_name)
      Slot.acquire(throttle_name, throttle_options_for(throttle_name))
    end

    def reenqueue(*args)
      fallback_method = [*throttle_options[:fallback_method]]
      self.class.public_send(*fallback_method, *args)
    end
  end
end
