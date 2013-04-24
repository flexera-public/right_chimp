#
# Run an SSH script
#
module Chimp
  class ExecCallback < Executor
    def run
      response = RestClient.get @uri
      if response.code > 199 and response.code < 300
        return true
      else
        return false
      end
    end
  end
end
