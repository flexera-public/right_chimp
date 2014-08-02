#
# Run a RightScript
#
require 'pry'
module Chimp
  class ExecRightScript < Executor
  
    def run
      options = {:ignore_lock => true}.merge(@inputs)
      
      if @timeout < 300
        Log.error "timeout was less than 5 minutes! resetting to 5 minutes"
        @timeout = 300
      end
    
      run_with_retry do
        audit_entry = server.show.run_executable(@exec, options)
        audit_entry.wait_for_state("completed", @timeout)
        @results = audit_entry.summary
      end
    end
    
    def describe_work
      puts "Describing work:"
      return "ExecRightScript job_id=#{@job_id} script=\"#{@exec[0]}\" server=\"#{@server.name}\""
    end
    
    def info
      puts "Info:"
      return @exec[0]
    end
    
    def target
      return @server['nickname']
    end
    
  end
end
