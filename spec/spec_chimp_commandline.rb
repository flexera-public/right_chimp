#
# Test chimpd client
#
$LOAD_PATH << File.dirname(__FILE__) + "/.."
require 'lib/right_chimp.rb'
require 'rspec'
require 'pp'

include Chimp

chimp_command = "CHIMP_TEST=true bundle exec bin/chimp --noprompt"
test_tag      = "--tag='info:deployment=moo:localring91'"
test_script   = "--script='SYS DNSMadeEasy Register Addresses'"

describe Chimp::Chimp do
  #
  # Selection options
  #
  #it "should not prompt when there is no action" do
  #  data =`CHIMP_TEST=true bundle exec bin/chimp #{test_tag}`
  #  $?.should == 0
  #  data.match("No actions to perform.").should != nil 
  #end

  #
  # RightScript execution
  #
  it "should run a rightscript with a tag query" do
    system("#{chimp_command} #{test_tag} #{test_script}")
    $?.should == 0
  end
  
  it "should run scripts on an array with a concurrency of 1 and a delay of 5" do
    system("#{chimp_command} --array='Core91' --concurrency=1 --delay=5 --script='SYS MAIL postfix configuration'")
    $?.should == 0
  end
  
  it "should run scripts on an array with a concurrency of 4 and a delay of 0" do
    system("#{chimp_command} --array='Core94' --array='Core91' --concurrency=4 --delay=0 --script='SYS MAIL postfix configuration'")
    $?.should == 0
  end
  
  #
  # chimpd submission
  #
  
  #it "should run a rightscript with a tag query via chimpd" do
  #  system('CHIMP_TEST=true bundle exec bin/chimpd')
  #  system('CHIMP_TEST=true bundle exec bin/chimp --chimpd --dry-run --noprompt --tag="info:deployment=moo:localring91" --script="SYS DNSMadeEasy Register Addresses"')
  #  $?.should == 0
  #  system('CHIMP_TEST=true bundle exec bin/chimpd --quit')
  #end
end


