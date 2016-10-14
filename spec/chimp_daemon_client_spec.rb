require 'spec_helper'
require 'pry'

describe Chimp::ChimpDaemonClient do
  before(:all) do
    @daemon = Chimp::ChimpDaemon.instance
    @daemon.verbose = false
    @daemon.concurrency = 3
    @daemon.spawn_queue_runner
    @daemon.spawn_webserver
  end

  after(:all) do
    @daemon.server.shutdown
  end

  let(:chimp_object) do
    c = Chimp::Chimp.new
    c.job_uuid = '123456'
    c
  end

  describe '#submit' do
    it 'should be able to send a job to the daemon' do
      expect(Chimp::ChimpDaemonClient.submit('localhost', '9055', chimp_object, '123456')).to eq(true)
    end

    it 'should increase the processing counter by 1' do
      start_value = @daemon.proc_counter
      Chimp::ChimpDaemonClient.submit('localhost', '9055', chimp_object, '123456')
      difference = @daemon.proc_counter - start_value
      expect(difference).to eq 1
    end
  end

  # describe '#retrieve_job_info' do
  #   it 'should correctly get a job ' do
  #     binding.pry
  #     Chimp::ChimpDaemonClient.retrieve_job_info('localhost', '9055')
  #   end
  # end

  describe '#retrieve_group_info' do
    it 'should retrieve a full group' do
      r = Chimp::ChimpDaemonClient.retrieve_group_info('localhost', '9055', 'default', :running)
      expect(r).to be_a(Array)
      expect(r[0]).to be_a(Chimp::ExecRightScript)
    end

    it 'should fail if the group doesnt exist' do
      s = Chimp::ChimpDaemonClient.retrieve_group_info('localhost', '9055', 'foobar', :running)
      expect(s).to be_a(NilClass)
    end
  end
  describe '#set_job_status'
  describe '#create_group'
  describe '#retry_group'
end
