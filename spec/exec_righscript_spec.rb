require 'spec_helper'

describe Chimp::ExecRightScript do
  let(:e) do
    e = Chimp::ExecRightScript.new
    e.job_uuid = '123456'
    e.time_start = Time.now
    e.time_end = e.time_start + 2
    # Need to setup e.exec
    e.exec = Chimp::Executable.new
    e.server = Chimp::Server.new
    e
  end

  before(:all) do
  end

  describe '#run' do
    it 'should pause' do
      # FIXME: probably need to workout some api stub/mocking
    end
  end

  describe '#describe_work' do
    it 'should return the formatted output' do
      expect(e.describe_work).to be_a(String)
    end
  end

  describe '#info' do
    it 'should be able to tell you the name' do
      expect(e.info).to be_a(String)
    end
  end

  describe '#target' do
    it 'should return the name of the server' do
      expect(e.target).to be_a(String)
    end
  end
end
