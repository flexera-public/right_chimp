#
# Superclass for Executors-- objects that run things on servers
#

module Chimp
  class Executor
    attr_accessor :server, :array, :exec, :inputs, :template, :owner, :group,
                  :job_id, :job_uuid, :job_notes, :status, :dry_run, :verbose, :quiet, :timeout,
                  :retry_count, :retry_sleep, :time_start, :time_end, :error

    attr_reader   :results

    STATUS_NONE =     :none
    STATUS_HOLDING =  :holding
    STATUS_RUNNING =  :running
    STATUS_RETRYING = :retrying
    STATUS_ERROR =    :error
    STATUS_DONE =     :done

    def initialize(h={})
      @server = h[:server]            || nil
      @array = h[:array]              || nil
      @template = h[:template]        || nil

      @job_id = h[:job_id]            || nil
      @job_uuid = h[:job_uuid]        || nil
      @job_notes = h[:job_notes]      || nil

      @group = h[:group]              || nil
      @exec = h[:exec]                || nil
      @inputs = h[:inputs]            || nil

      @verbose = h[:verbose]          || false

      @retry_count = h[:retry_count].to_i || 0
      @retry_sleep = h[:retry_sleep].to_i || 30
      @timeout = h[:timeout].to_i         || 3600

      @error = nil
      @status = STATUS_NONE
      @owner = nil
      @dry_run = false
      @quiet = false

      @time_start = nil
      @time_end = nil
    end

    #
    # Return total execution time (real) of a job
    #
    def get_total_exec_time
      if @time_start == nil
        return 0
      elsif @time_end == nil
        return Time.now.to_i - @time_start.to_i
      else
        return @time_end.to_i- @time_start.to_i
      end
    end

    #
    # Convenience method to queue a held job
    #
    def queue
      @group.queue(self.job_id)
    end

    #
    # Convenience method to requeue
    #
    def requeue
      @group.requeue(self.job_id)
    end

    #
    # Convenience method to cancel
    #
    def cancel
      @group.cancel(self.job_id)
    end

    def run
      raise "run method must be overridden"
    end

    #
    # return info on what this executor does -- eg name of script or command
    #
    def info
      raise "unimplemented"
    end

    def target
      return "UNKNOWN"
    end


    protected

    #
    # Run a unit of work with retries
    # This is called from the subclass with a code block to yield to
    #
    def run_with_retry(&block)
      Log.debug "Running job '#{@job_id}' with status '#{@status}'"

      @status = STATUS_RUNNING
      @time_start = Time.now

      Log.info self.describe_work_start unless @quiet

      #
      # The inner level of exception handling here tries to catch anything
      # that can be easily retired or failed-- normal exceptions.
      #
      # The outer level of exception handling handles weird stuff; for example,
      # sometimes rest_connection raises RuntimeError exceptions...
      #
      # This fixes acu75562.
      #
      begin
        begin
          yield if not @dry_run

          if @owner != nil
            @status = STATUS_DONE
            @group.job_completed
          else
            Log.warn "[#{@job_uuid}][#{@job_id}] Ownership of job_id #{job_id} lost. User cancelled operation?"
          end

        rescue SystemExit, Interrupt => ex
          $stderr.puts "Exiting!"
          raise ex

        rescue Interrupt => ex
          name = @array['name'] if @array
          name = @server['name'] || @server['nickname'] if @server
          Log.error self.describe_work_error

          if @retry_count > 0
            @status = STATUS_RETRYING
            Log.error "[#{@job_uuid}][#{@job_id}] Error executing on \"#{name}\". Retrying in #{@retry_sleep} seconds..."
            @retry_count -= 1
            sleep @retry_sleep
            retry
          end

          @status = STATUS_ERROR
          @error = ex
          Log.error "[#{@job_uuid}][#{@job_id}] Error executing on \"#{name}\": #{ex}"

        ensure
          @time_end = Time.now
          Log.info self.describe_work_done unless @quiet
        end

      rescue RuntimeError => ex
        err = ex.message + "IP: #{@server.params["ip_address"]}\n" if @server.params['ip_address']
        err += " Group: #{@group.group_id}\n" if @group.group_id
        err += " Notes: #{@job_notes}\n" if @job_notes
        Log.error "[#{@job_uuid}][#{@job_id}] Caught RuntimeError: #{err} Aborting job.\n"
        @status = STATUS_ERROR
        @error = ex
      end
    end

    #
    # This method should be overridden on Executor subclasses
    # to provide a human readable description of the work
    # being performed.
    #
    def describe_work
      return "#{self.class.name} job_id=#{@job_id}"
    end

    def describe_work_start
      return("#{self.describe_work} status=START")
    end

    def describe_work_done
      return("#{self.describe_work} status=END time=#{@time_end.to_i-@time_start.to_i}s")
    end

    def describe_work_done_long
      return("#{self.describe_work} status=END time_start=#{@time_start.to_i} time_end=#{@time_end.to_i} time_total=#{@time_end.to_i-@time_start.to_i}")
    end

    def describe_work_error
      return("#{self.describe_work} status=ERROR")
    end
  end
end
