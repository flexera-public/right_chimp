#
# Test QueueWorker
#
$LOAD_PATH << File.dirname(__FILE__) + "/.."
require 'lib/right_chimp.rb'
require 'rspec'

include Chimp

describe QueueWorker do
  it "should instantiate" do
    q = QueueWorker.new
    q.delay = 10
    q.retry_count = 10
    q.never_exit = false
    
    ChimpQueue.instance.group = {}

    q.delay.should == 10
    q.retry_count.should == 10
    q.never_exit.should == false
  end
  
  #it "should run" do
  #  q = QueueWorker.new
  #  q.run
  #end
  
end

