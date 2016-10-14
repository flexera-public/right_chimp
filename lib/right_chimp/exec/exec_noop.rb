module Chimp
  class ExecNoop < Executor
    def run
      run_with_retry do
        # do nothing
      end
    end
  end
end
