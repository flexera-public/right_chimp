module Chimp

  #
  # Factory
  #
  class ExecutionGroupFactory
    def self.from_type(type)
      if type == :serial
        return SerialExecutionGroup.new(nil)
      elsif type == :parallel
        return ParallelExecutionGroup.new(nil)
      else
        raise "invalid execution group type specified"
      end
    end
  end

  #
  # An ExecutionGroup contains a set of Executors to be processed
  #
  # Only the subclasses SerialExecutionGroup and ParallelExecutionGroup
  # should be used directly.
  #
  class ExecutionGroup
    attr_accessor :group_id, :description, :concurrency
    attr_reader   :time_start, :time_end

    def initialize(new_group_id=nil)
      @group_id = new_group_id
      @queue = []
      @jobs_by_id = {}
      @log = nil
      @time_start = nil
      @time_end = nil
      @concurrency = 1
    end

    #
    # Add something to the work queue
    #
    def push(j)
      raise "invalid work" if j == nil
      j.job_id = IDManager.get if j.job_id == nil
      j.group = self
      @queue.push(j)
      @jobs_by_id[j.job_id] = j
    end

    #
    # Take something from the queue
    #
    def shift
      updated_queue = []
      found_job = nil
      @queue.each do |job|
        if found_job || job.status == Executor::STATUS_HOLDING
          updated_queue.push(job)
        elsif job.status == Executor::STATUS_NONE
          found_job = job
        end
      end
      @queue = updated_queue
      @time_start = Time.now if @time_start == nil
      return found_job
    end

    #
    # Return a hash of the results
    #
    def results
      return self.get_jobs.map do |task|
        next if task == nil
        next if task.server == nil
        {
          :job_id => task.job_id,
          :name   => task.info[0],
          :host   => task.server.name,
          :status => task.status,
          :error  => task.error,
          :total  => self.get_total_execution_time(task.status, task.time_start, task.time_end),
          :start  => task.time_start,
          :end    => task.time_end,
          :worker => task
        }
      end
    end

    #
    # Size of the active queue
    #
    def size
      return @queue.size
    end

    #
    # Sort queue by server nickname
    #
    def sort!
      if @queue != nil
        @queue.sort! do |a,b|
          a.server.nickname <=> b.server.nickname
        end
      end
    end

    #
    # Reset the queue
    #
    def reset!
      @queue = []
    end

    #
    # Get all jobs
    #
    def get_jobs
      @jobs_by_id.values
    end

    #
    # Get all job ids
    #
    def get_job_ids
      @jobs_by_id.keys
    end

    #
    # Get a particular job
    #
    def get_job(i)
      @jobs_by_id[i]
    end

    #
    # Get jobs by status
    #
    def get_jobs_by_status(status)
      r = []
      @jobs_by_id.values.each do |i|
        r << i if i.status == status.to_sym || status.to_sym == :all
      end
      return r
    end

    def job_completed
      @time_end = Time.now
    end

    #
    # Reset all jobs and bulk set them
    #
    def set_jobs(jobs=[])
      self.reset!
      jobs.each do |job|
        self.push(job)
      end
    end

    #
    # An execution group is "ready" if it has work that can be done;
    # see implementation in child classes.
    #
    def ready?
      raise "unimplemented"
    end

    #
    # An execution group is "done" if nothing is queued or running
    # and at least one job has completed.
    #
    def done?
      return (
        get_jobs_by_status(Executor::STATUS_NONE).size == 0 &&
        get_jobs_by_status(Executor::STATUS_RUNNING).size == 0 &&
         get_jobs_by_status(Executor::STATUS_DONE).size > 0
        )
    end

    #
    # Is this execution group running anything?
    #
    def running?
      total_jobs_running = get_jobs_by_status(Executor::STATUS_NONE).size +
          get_jobs_by_status(Executor::STATUS_RUNNING).size +
          get_jobs_by_status(Executor::STATUS_RETRYING).size
      return(total_jobs_running > 0)
    end

    #
    # Requeue all failed jobs
    #
    def requeue_failed_jobs!
      get_jobs_by_status(Executor::STATUS_ERROR).each do |job|
        requeue(job.job_id)
      end
    end

    #
    # Queue a held job by id
    #
    def queue(id)
      puts "Queuing held job id #{id}"
      job = @jobs_by_id[id]
      job.owner = nil
      job.time_start = Time.now
      job.time_end = nil
      job.status = Executor::STATUS_NONE
      self.push(job)
    end

    #
    # Requeue a job by id
    #
    def requeue(id)
      puts "Requeuing job id #{id}"
      job = @jobs_by_id[id]
      job.status = Executor::STATUS_NONE
      job.owner = nil
      job.time_start = Time.now
      job.time_end = nil
      self.push(job)
    end

    #
    # Cancel a job by id
    #
    def cancel(id)
      Log.warn "Cancelling job id #{id}"
      job = @jobs_by_id[id]
      job.status = Executor::STATUS_ERROR
      job.owner = nil
      job.time_end = Time.now
      @queue.delete(job)
    end

    #
    # Return total execution time
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
    # Print out ExecutionGroup information
    #
    def to_s
      return "#{self.class}[#{group_id}]: ready=#{self.ready?} total_jobs=#{@jobs_by_id.size} queued_jobs=#{self.size}"
    end

    ###################################
    protected
    ###################################

    #
    # Return total execution time or -1 for errors
    #
    def get_total_execution_time(status, time_begin, time_end)
      return(status != :error ? time_end.to_i - time_begin.to_i : -1)
    end

  end

  #
  # SerialExecutionGroup: run only one job at a time
  #
  class SerialExecutionGroup < ExecutionGroup
    def ready?
      return get_jobs_by_status(Executor::STATUS_RUNNING).size == 0 && get_jobs_by_status(Executor::STATUS_NONE).size > 0
    end

    def short_name
      "S"
    end
  end

  #
  # ParallelExecutionGroup: run multiple jobs at once
  #
  class ParallelExecutionGroup < ExecutionGroup
    def initialize(new_group_id)
      super(new_group_id)
      @concurrency = 25
    end

    def ready?
      return (get_jobs_by_status(Executor::STATUS_NONE).size > 0) # and get_jobs_by_status(Executor::STATUS_RUNNING).size < @concurrency)
    end

    def short_name
      "P"
    end
  end
end
