$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require 'sidekiq/throttle'
Dir[File.dirname(__FILE__) + '/../lib/sidekiq/throttle/*.rb'].each { |file| require file }

require 'minitest/autorun'
require 'mocha/minitest'
require 'pry'

require 'timecop'
require 'mock_redis'

class ActiveSupport::TestCase
  def teardown
    Sidekiq.redis.flushall
    Timecop.return
  end
end

module Sidekiq
  module Test
    def redis
      @redis ||= ::MockRedis.new
    end
  end

  extend Sidekiq::Test unless Sidekiq.respond_to?(:redis)
end
