#
# Test chimpd client
#
$LOAD_PATH << File.dirname(__FILE__) + "/.."
require 'lib/right_chimp.rb'
require 'rspec'
require 'pp'

include Chimp

host = "localhost"
port = "9055"

describe Chimp::ChimpDaemonClient do
  before :all do
    @c = ChimpDaemon.new
    @c.verbose = false
    @c.concurrency = 3
    @c.spawn_queue_runner
    @c.spawn_webserver
  end

  after :all do
    @c.quit if @c
  end

  #it "can quit a chimpd" do
  #  response_code = ChimpDaemonClient.quit(host, port)
  #  response_code.should == 200
  #end
  
  #
  # .submit
  #
  it "can submit work to chimpd" do
    c = Chimp::Chimp.new
    c.tags = ["service:auditor=true"]
    c.script = "SYS DNSMadeEasy Register Addresses"
    c.dry_run = false
    ChimpDaemonClient.submit(host, port, c)
  end

end

