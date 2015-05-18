#
# Run an SSH script
#
module Chimp
  class ExecSSH < Executor
    attr_accessor :ssh_user
    
    def initialize(h={})
      super(h)
      @ssh_user = h[:ssh_user]
    end
    
    def run
      host = @server.ip_address || nil
      @ssh_user ||= "root"

      run_with_retry do
        puts "ssh #{@ssh_user}@#{host} \"#{@exec}\""
        success = system("ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no #{@ssh_user}@#{host} \"#{@exec}\"")
        
        if not $?.success?
          raise "SSH failed with status: #{$?}"
        end
      end
    end
    
    def describe_work
      return "ExecSSH job_id=#{@job_id} command=\"#{@exec}\" server=\"#{@server.nickname}\""
    end
    
    def info
      return @exec.to_s
    end
    
    def target
      return @server.nickname
    end
    
  end
end