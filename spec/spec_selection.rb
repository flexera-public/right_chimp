#
# Test Chimp
#
$LOAD_PATH << File.dirname(__FILE__) + "/.."
require 'lib/right_chimp.rb'
require 'rspec'

describe Chimp::Chimp do
  before :each do
    @c = Chimp::Chimp.new
    @c.quiet = true
    @c.prompt = false
    @c.progress = false
    @c.interactive = false
  end

  it "performs a tag query" do
    @c.tags = ['info:static_asset=true']
    @c.servers.size.should > 0
  end

  it "performs a deployment query" do
    @c.deployment_names = ['moo:']
    @c.run
    @c.servers.size.should > 0
  end

  it "performs an array query" do
    @c.array_names = ['Services']
    @c.run
  end
end
