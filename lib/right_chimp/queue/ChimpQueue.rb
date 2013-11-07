module Chimp
  #
  # The ChimpQueue is a singleton that contains the
  # chimp work queue
  #
  class ChimpQueue
    include Singleton
    
    attr_accessor :delay, :retry_count, :max_threads, :group
    
    def initialize
      @delay = 0
      @retry_count = 0
      @max_threads = 10
      @workers_never_exit = true
      @threads = []
      @semaphore = Mutex.new
      self.reset!
    end
    
    #
    # Reset the queue and the :default group
    #
    # This doesn't do anything to the groups's jobs
    #
    def reset!
      @group = {}
      @group[:default] = ParallelExecutionGroup.new(:default)
    end
    
    #
    # Start up queue runners
    #
    def start
      self.sort_queues!
      
      for i in (1..max_threads)
        @threads << Thread.new(i) do
          worker = QueueWorker.new
          worker.delay = @delay
          worker.retry_count = @retry_count
          worker.run
        end
      end
    end
    
    #
    # Push a task into the queue
    #
    def push(g, w)
      if w.exec.kind_of?(Hash)
        Log.debug "Pushing job '#{w.exec['right_script']['name']}' into group '#{g}'"
      end

      raise "no group specified" unless g
      create_group(g) if not ChimpQueue[g]
      ChimpQueue[g].push(w)
    end
    
    def create_group(name, type = :parallel, concurrency = 1)
      Log.debug "Creating new execution group #{name} type=#{type} concurrency=#{concurrency}"
      new_group = ExecutionGroupFactory.from_type(type)
      new_group.group_id = name
      new_group.concurrency = concurrency
      ChimpQueue[name] = new_group
    end
    
    #
    # Grab the oldest work item available
    #
    def shift
      r = nil
      @semaphore.synchronize do
        @group.values.each do |group|
          if group.ready?
            r = group.shift
            Log.debug "Shifting job '#{r.job_id}' from group '#{group.group_id}'"
            break
          end
        end      
      end
      return(r)
    end
    
    #
    # Wait until a group is done
    #
    def wait_until_done(g, &block)
      while @group[g].running? 
        @threads.each do |t|
          t.join(1)
          yield          
        end
      end
    end
    
    #
    # Quit - empty the queue and wait for remaining jobs to complete
    # 
    def quit
      i = 0
      @group.keys.each do |group|
        wait_until_done(group) do
          if i < 30
            sleep 1
            i += 1
            print "."
          else
            break
          end
        end
      end
      
      @threads.each { |t| t.kill }
      puts " done."
    end
    
    #
    # Run all threads forever (used by chimpd)
    #
    def run_threads
      @threads.each do |t| 
        t.join(5)
      end
    end
    
    #
    # return the total number of queued (non-executing) objects
    #
    def size
      s = 0
      @group.values.each do |group|
        s += group.size
      end
      return(s)
    end
    
    #
    # Allow the groups to be accessed as ChimpQueue.group[:foo]
    #
    def self.[](group)
      return ChimpQueue.instance.group[group]
    end
    
    def self.[]=(k,v)
      ChimpQueue.instance.group[k] = v
    end
    
    #
    # Return an array of all jobs with the requested
    # status.
    #
    def get_jobs_by_status(status)
      r = []
      @group.values.each do |group| 
        v = group.get_jobs_by_status(status)
        if v != nil and v != []
          r += v
        end
      end
      
      return r
    end
    
    def get_job(id)
      jobs = self.get_jobs
      
      jobs.each do |j|
        return j if j.job_id == id
      end
    end
    
    def get_jobs
      r = []
      @group.values.each do |group|
        group.get_jobs.each { |job| r << job }
      end
      
      return r
    end
    
    ############################################################# 
    protected
    
    #
    # Sort all the things, er, queues
    #
    def sort_queues!
      return @group.values.each { |group| group.sort! }
    end
    
  end
end
