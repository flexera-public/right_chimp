#
# Test chimpd client
#
$LOAD_PATH << File.dirname(__FILE__) + "/.."

require 'lib/right_chimp.rb'
require 'rspec'
require 'pp'

include Chimp

describe Chimp::ExecRightScript do
  it "can select servers with a tag query" do
    c = Chimp::Chimp.new
    c.tags = ["info:deployment=moo:localring91"]
    c.script = "SYS DNSMadeEasy Register Addresses"
    c.dry_run = false
    c.run
  end
end
