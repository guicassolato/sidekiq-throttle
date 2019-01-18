# Sidekiq::Throttle

sidekiq-throttle allows to rate limit and control the execution of concurrent [Sidekiq](https://github.com/mperham/sidekiq) workers.

You can limit the number of slots available to be taken (acquired) by workers, like a lock, thus establishing the maximum number of jobs performing in parallel. You can also set a frequency (duration) for each slot to be held.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-throttle'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-throttle

## Usage

```ruby
require 'sidekiq/throttle'

class MyWorker
  include Sidekiq::Worker
  include Sidekie::Throttle

  sidekiq_options throttle: { number_of_slots: 3, duration: 30.seconds }

  def perform(*args)
    throttle(:my_throttle, *args) do
      # my job code goes here
    end
  end
end
```

### Throttle options

`number_of_slots`: maximum number of workers running in parallel (default: 1).

`duration`: each slot is locked exclusively to one job for this given amount of time or until the job finishes, whichever lasts longer (default: 30s).

`fallback_method`: in case a worker thread fails to acquire a slot, this fallback method is invoked, receiving the arguments of the job itself as parameters (default: `:perform_async`).

#### Defaults

If not specified otherwise, the default options for your throttle are:

```ruby
number_of_slots: 1                 # maximum 1 worker running at a time
duration: 30.seconds               # slot is locked to your job for 30 seconds or until the job finishes, whichever lasts longer
fallback_method: :perform_async    # in case a new a worker thread fails to acquire a slot of the throttle to perform, it is re-enqueued with the same parameters
```

#### Specific throttle options

You can also define options specifically for your throttle, in contraposition to options that apply to all throttles opened inside the same Sidekiq worker class:

```ruby
sidekiq_options throttle: { my_throttle: { number_of_slots: 3, duration: 30.seconds } }
```

### Fallback function

By default,whenever a worker thread fails to acquire a slot of the throttle to perform, the job is re-enqueued with the same parameters by calling Sidekiq's `perform_async`. You can change the fallback function, for example, to use `perform_in` instead:

```ruby
sidekiq_options throttle: { fallback_method: [:perform_in, 1.minute] }
```

Or you may prefer defining your own instance method for the throttle to fallback to in case a job fails to acquire a slot:

```ruby
require 'sidekiq/throttle'

class MyWorker
  include Sidekiq::Worker
  include Sidekie::Throttle

  sidekiq_options throttle: { my_throttle: { number_of_slots: 3, duration: 30.seconds, fallback_method: :my_custom_fallback } }

  def perform(*args)
    throttle(:my_throttle, *args) do
      # my job code goes here
    end
  end

  def my_custom_fallback(*)
    raise 'No slots available now. Sidekiq, please retry on your own way!'
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## TODOs
- Add a default expire/slot timeout, just in case the user never calls `Slot#release!`
- Implement a delay between throttle openings
- Make the throttle duration independent of the slots currently in use, instead of each slot having its own duration

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/guicassolato/sidekiq-throttle. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Sidekiq::Throttle project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/guicassolato/sidekiq-throttle/blob/master/CODE_OF_CONDUCT.md).
