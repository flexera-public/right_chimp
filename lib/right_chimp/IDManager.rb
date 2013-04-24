#
# Utility class for generating sequential job ids
#
module Chimp
  class IDManager
    @@id = 0
    @@mutex = Mutex.new
    
    def self.get
      r = nil
      @@mutex.synchronize do
        @@id = @@id + 1
        r = @@id
      end
      return r
    end
  end
end
