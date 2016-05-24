#
# Run a RightScript
#
module Chimp
  class ExecRightScript < Executor

    attr_accessor :audit_entry_data, :audit_entry_url

    def run
      options = { ignore_lock: true }.merge(@inputs)

      if @timeout < 300
        Log.error 'timeout was less than 5 minutes! resetting to 5 minutes'
        @timeout = 300
      end

      run_with_retry do
        task=Task.new
        task.tasker = @server.run_executable(@exec, options)
        @audit_entry_url = task.friendly_url
        task.wait_for_state('completed', @timeout)
        @results = task.state
        @audit_entry_data = task.details
      end
    end

    def describe_work
      "[#{@job_uuid}] ExecRightScript job_id=#{@job_id} script=\"#{@exec.params['right_script']['name']}\" server=\"#{@server.nickname}\""
    end

    def info
      @exec.params['right_script']['name']
    end

    def target
       @server.nickname
    end

  end
end
