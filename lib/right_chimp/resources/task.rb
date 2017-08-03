#
# Extra classes needed to operate with Chimp
#
module Chimp
  #
  # This class allows to check on the status of any of the tasks created.
  #
  class Task
    attr_writer :tasker
    attr_reader :tasker

    attr_accessor :api_polling_rate
    def initialize
      self.api_polling_rate = ENV['API_POLLING_RATE'].to_i || 30
    end

    def wait_for_state(desired_state, timeout = 900)
      while timeout > 0
        # Make compatible with RL10.
        status = state.downcase
        return true if status.match(desired_state)
        friendly_url = Connection.audit_url + '/audit_entries/'
        friendly_url += href.split(/\//).last
        friendly_url = friendly_url.gsub('ae-', '')
        if status.match('failed') || status.match('aborted')
          raise "FATAL error, #{status}\n\n Audit: #{friendly_url}\n "
        end
        Log.debug "Polling again in #{self.api_polling_rate}"
        sleep self.api_polling_rate
        timeout -= self.api_polling_rate
      end
      raise "FATAL: Timeout waiting for Executable to complete.  State was #{status}" if timeout <= 0
    end

    def wait_for_completed(timeout = 900)
      wait_for_state('completed', timeout)
    end

    def state
      tasker.show.summary
    end

    def href
      tasker.href
    end

    def friendly_url
      friendly_url = Connection.audit_url + '/audit_entries/'
      friendly_url += href.split(/\//).last
      friendly_url = friendly_url.gsub('ae-', '')
      friendly_url
    end

    def details
      tasker.show(view: 'extended').detail
    end
  end
end
