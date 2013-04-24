#
# Run a RightScript on an array
#
module Chimp
  class ExecArray < Executor
    def run
      run_with_retry do
        audit_entry = []
        
        #
        # If we have API 0.1 access, then use the 0.1 version of this call.
        # Otherwise use the 1.0 version.
        #
        if @array.internal
          audit_entry = @array.internal.run_script_on_instances(@exec, @server['href'], {})
        else
          audit_entry = @array.run_script_on_instances(@exec, @server['href'], {})
        end
        
        if audit_entry
          audit_entry.each do |a|
            a.wait_for_completed
          end
        else
          Log.warn "No audit entries returned for job_id=#{@job_id}"
        end
      end
    end
    
    def describe_work
      return "ExecArray job_id=#{@job_id} script=\"#{@exec['right_script']['name']}\" server=\"#{@server['nickname']}\""
    end
    
    def info
      return @exec['right_script']['name']
    end
    
    def target
      return @server['nickname']
    end
    
  end
end
