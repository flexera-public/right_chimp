#
# QueueWorker objects take work from the Queue and process it
# Each QueueWorker runs in its own thread... nothing fancy going on here
#
module Chimp
  class QueueWorker
    attr_accessor :delay, :retry_count, :never_exit, :dry_run

    def initialize
      @delay = 0
      @retry_count = 0
      @never_exit = true
      @dry_run = false
    end

    #
    # Grab work items from the ChimpQueue and process them
    # Only stop is @ever_exit is false
    #
    def run
      while @never_exit
        work_item = ChimpQueue.instance.shift()

        begin
          if work_item != nil
            work_item.retry_count = @retry_count
            work_item.owner = Thread.current.object_id
            work_item.run
            if @dry_run == true
              puts "DRY-RUN: I would sleep for #{@delay} seconds here"
            else
              sleep @delay 
            end
          else
            sleep 1
          end

        rescue Exception => ex
          Log.error "Exception in QueueWorker.run: #{ex}"
          Log.debug ex.inspect
          Log.debug ex.backtrace

          work_item.status = Executor::STATUS_ERROR
          work_item.error = ex
        end
      end
    end

  end
end
