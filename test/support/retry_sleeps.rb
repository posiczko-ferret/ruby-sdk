require "faraday/retry"

# Records faraday-retry's backoff instead of sleeping, so retry tests run fast
# and can assert on the waits.
module RetrySleeps
  def self.recorded
    Thread.current[:procore_retry_sleeps] ||= []
  end

  def sleep(seconds)
    RetrySleeps.recorded << seconds
  end
end

Faraday::Retry::Middleware.prepend(RetrySleeps)
