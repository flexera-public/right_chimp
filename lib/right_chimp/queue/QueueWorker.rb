#
# QueueWorker objects take work from the Queue and process it
# Each QueueWorker runs in its own thread... nothing fancy going on here
#
module Chimp
  class QueueWorker
    attr_accessor :delay, :retry_count, :never_exit
    
    def initialize
      @delay = 0
      @retry_count = 0
      @never_exit = true
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
            sleep @delay
          else
            sleep 1
          end
        
        rescue StandardError => ex
          $stderr.puts "Exception in QueueWorker.run: #{ex}"
          puts ex.inspect
          puts ex.backtrace
        end
      end
    end
    
  end
end
