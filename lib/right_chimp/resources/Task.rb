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

    def wait_for_state(desired_state, timeout=900)
      while(timeout > 0)
        state=self.tasker.show.summary
        return true if self.state.match(desired_state)
        friendly_url = Connection.audit_url + '/audit_entries/'
        friendly_url += self.href.split(/\//).last
        friendly_url = friendly_url.gsub('ae-', '')
        raise "FATAL error, #{tasker.show.summary}\n\n Audit: #{friendly_url}\n " if self.state.match("failed")
        sleep 30
        timeout -= 30
      end
      raise "FATAL: Timeout waiting for Executable to complete.  State was #{self.state}" if timeout <= 0
    end

    def wait_for_completed(timeout=900)
      wait_for_state('completed', timeout)
    end

    def state
      self.tasker.show.summary
    end

    def href
      self.tasker.href
    end

    def friendly_url
      friendly_url = Connection.audit_url+"/audit_entries/"
      friendly_url += self.href.split(/\//).last
      friendly_url = friendly_url.gsub("ae-","")
      friendly_url
    end

    def details
      self.tasker.show(:view => "extended").detail
    end
  end
end
