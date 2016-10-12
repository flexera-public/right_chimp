# #
# # Test chimpd client
# #
# $LOAD_PATH << File.dirname(__FILE__) + "/.."
# require 'lib/right_chimp.rb'
# require 'rspec'
# require 'pp'
#
# include Chimp
#
# chimp_command = 'CHIMP_TEST=true bundle exec bin/chimp --noprompt'
# test_tag      = '--tag=info:static_asset=true'
# test_script   = '--script="Sys set hostname"'
#
# describe Chimp::Chimp do
#   before :all do
#     creds = YAML.load_file("#{ENV['HOME']}/.rest_connection/rest_api_config.yaml")
#     creds[:account] = File.basename(creds[:api_url])
#     if creds[:account]  != '9202'
#       puts 'Not pointing to 9202, will fail'
#     end
#   end
#   #
#   # Selection options
#   #
#   #it "should not prompt when there is no action" do
#   #  data =`CHIMP_TEST=true bundle exec bin/chimp #{test_tag}`
#   #  $?.should == 0
#   #  data.match("No actions to perform.").should != nil
#   #end
#
#   #
#   # RightScript execution
#   #
#   it 'should run a rightscript with a tag query' do
#     system("#{chimp_command} #{test_tag} #{test_script}")
#     $?.should == 0
#   end
#
#   it 'should run scripts on an array with a concurrency of 1 and a delay of 5' do
#     system("#{chimp_command} --array='Services' --concurrency=1 --delay=5 #{test_script}")
#     $?.should == 0
#   end
#
#   it 'should run scripts on an array with a concurrency of 4 and a delay of 0' do
#     system("#{chimp_command} --array='Services' --array='Right_Api' --concurrency=4 --delay=0 #{test_script}")
#     $?.should == 0
#   end
#
#   #
#   # chimpd submission
#   #
#
#   #it "should run a rightscript with a tag query via chimpd" do
#   #  system('CHIMP_TEST=true bundle exec bin/chimpd')
#   #  system('CHIMP_TEST=true bundle exec bin/chimp --chimpd --dry-run --noprompt --tag="info:deployment=moo:localring91" --script="SYS DNSMadeEasy Register Addresses"')
#   #  $?.should == 0
#   #  system('CHIMP_TEST=true bundle exec bin/chimpd --quit')
#   #end
# end
