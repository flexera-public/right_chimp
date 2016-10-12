# #
# # Test chimpd client
# #
# $LOAD_PATH << File.dirname(__FILE__) + "/.."
#
# require 'lib/right_chimp.rb'
# require 'rspec'
# require 'pp'
#
# include Chimp
#
# describe Chimp::ExecRightScript do
#   it 'can select servers with a tag query' do
#     c = Chimp::Chimp.new
#     c.tags = ['info:statics_test=true']
#     c.script = 'TEST CHIMP success'
#     c.dry_run = false
#     c.run
#   end
# end
