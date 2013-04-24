#
# Run a RightScript
#
module Chimp
  class ExecRightScript < Executor
  
    def run
      options = {:ignore_lock => true}.merge(@inputs)
      
      if @timeout < 300
        Log.error "timeout was less than 5 minutes! resetting to 5 minutes"
        @timeout = 300
      end
    
      run_with_retry do
        audit_entry = server.run_executable(@exec, options)
        audit_entry.wait_for_state("completed", @timeout)
        @results = audit_entry.summary
      end
    end
    
    def describe_work
      return "ExecRightScript job_id=#{@job_id} script=\"#{@exec['right_script']['name']}\" server=\"#{@server['nickname']}\""
    end
    
    def info
      return @exec['right_script']['name']
    end
    
    def target
      return @server['nickname']
    end
    
  end
end
