#
# Test QueueWorker
#
$LOAD_PATH << File.dirname(__FILE__) + "/.."
require 'lib/right_chimp.rb'
require 'rspec'

include Chimp

describe SerialExecutionGroup do
  before :each do
    @eg = SerialExecutionGroup.new(:test)
  end

  #
  # .ready?
  #
  it "should be ready when it has work in its queue" do
    @eg.ready?.should == false
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.ready?.should == true
  end
  
  it "should not be ready while a job is executing" do
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.push(ExecNoop.new(:job_id => 1))
    @eg.get_job(0).status = Executor::STATUS_RUNNING    
    @eg.ready?.should == false
  end
  
  #
  # .done?
  #
  it "should not be done when it has work in its queue" do
    @eg.done?.should == true
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.done?.should == false
  end
  
  #
  # .size
  #
  it "should be able to report the correct number of items in its queue" do
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.push(ExecNoop.new(:job_id => 1))
    @eg.push(ExecNoop.new(:job_id => 2))
    @eg.push(ExecNoop.new(:job_id => 3))
    @eg.push(ExecNoop.new(:job_id => 4))
    
    @eg.size.should == 5
    
    @eg.shift
    @eg.size.should == 4
    
    @eg.shift
    @eg.size.should == 3
  end
  
  #
  # .sort!
  #
  it "should be able to sort its queue by server name" do
    @eg.push(ExecNoop.new(:job_id => 1, :server => { "nickname" => "BBB", "name" => "BBB"}))
    @eg.push(ExecNoop.new(:job_id => 1, :server => { "nickname" => "CCC", "name" => "CCC"}))
    @eg.push(ExecNoop.new(:job_id => 0, :server => { "nickname" => "AAA", "name" => "AAA"}))
    @eg.sort!
  end
  
  #
  # .running?
  #
  it "should tell us whether it is running" do
    @eg.running?.should == false
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.running?.should == true
  end
  
  #
  # .requeue(id)
  #
  it "should requeue jobs correctly" do
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.reset!
    @eg.size.should == 0
    @eg.requeue(0)
    @eg.size.should == 1
  end
  
  #
  # .requeue_failed_jobs
  #
  it "should requeue all failed jobs" do
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.reset!
    @eg.size.should == 0
    
    @eg.get_job(0).status = Executor::STATUS_ERROR
    @eg.requeue_failed_jobs!
    @eg.size.should == 1
  end
  
  #
  # .cancel(id)
  #
  it "should cancel a job" do
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.size.should == 1
    @eg.cancel(0)
    @eg.size.should == 0
  end
  
end

describe ParallelExecutionGroup do
  before :each do
    @eg = ParallelExecutionGroup.new(:test)
  end

  #
  # .ready?
  #
  it "should be ready when it has work in its queue" do
    @eg.ready?.should == false
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.push(ExecNoop.new(:job_id => 1))
    @eg.ready?.should == true
  end
  
  it "should be ready while a job is executing" do
    @eg.push(ExecNoop.new(:job_id => 0))
    @eg.push(ExecNoop.new(:job_id => 1))
    @eg.get_job(0).status = Executor::STATUS_RUNNING    
    @eg.ready?.should == true
  end
end