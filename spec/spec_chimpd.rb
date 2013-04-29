#
# Test chimpd
#
$LOAD_PATH << File.dirname(__FILE__) + "/.."
require 'lib/right_chimp.rb'
require 'rspec'
require 'pp'

include Chimp

uri = 

describe Chimp::ChimpDaemon do
  before :all do
    @c = ChimpDaemon.instance
    @c.spawn_queue_runner
    @c.spawn_webserver
  end
  
  #
  # .spawn_queue_runner
  #
  it "should have 50 threads" do
    ChimpQueue.instance.max_threads.should == 50
  end

  #
  # .quit
  #
  after :all do
    @c.quit
  end
end
