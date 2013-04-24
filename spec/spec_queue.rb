#
# Test ChimpQueue
#

require 'lib/right_chimp.rb'
require 'rspec'

include Chimp

describe ChimpQueue do
  before :all do
    @queue = ChimpQueue.instance
    @queue.max_threads = 3
    @queue.start
  end
  
  before :each do
    @queue.reset!
  end
  
  it "should accept work" do
    @queue.push(:default, ExecNoop.new(:job_id => 0))
    @queue.group[:default].get_job(0).status.should == Executor::STATUS_NONE
  end
  
  it "should distribute work" do
    @queue.push(:default, ExecNoop.new(:job_id => 0))
    @queue.shift.status.should == Executor::STATUS_NONE
  end
  
  it "should process the queue" do
    @queue.push(:default, ExecNoop.new(:job_id => 0))
    @queue.wait_until_done(:default) { }
    @queue.group[:default].get_job(0).status.should == Executor::STATUS_DONE
  end
end

