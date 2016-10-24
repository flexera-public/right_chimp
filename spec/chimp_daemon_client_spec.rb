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
      expect {
        Chimp::ChimpDaemonClient.retrieve_group_info('localhost', '9055', 'foobar', :running)
      }.to raise_error(RestClient::ResourceNotFound)
    end
  end

  # # this basically tests updating the status of a job
  # describe '#set_job_status' do
  #   it 'should change the status of a job' do
  #     Chimp::ChimpDaemonClient.set_job_status('localhost', '9055', '0', :running)
  #   end
  #
  #   it 'should be unable to update a job that doesnt exist' do
  #
  #   end
  # end

  describe '#create_group' do
    it 'should create a parallel group' do
      expect(Chimp::ChimpDaemonClient.create_group('localhost', '9055', 'paragroup', :parallel, '3')).to eq(false)
      expect(@daemon.queue.group['paragroup']).to be_a(Chimp::ParallelExecutionGroup)
      expect(@daemon.queue.group['paragroup'].concurrency).to eq('3')
    end

    it 'should create a serial group' do
      expect(Chimp::ChimpDaemonClient.create_group('localhost', '9055', 'serialgroup', :serial, '2')).to eq(false)
      expect(@daemon.queue.group['serialgroup']).to be_a(Chimp::SerialExecutionGroup)
      expect(@daemon.queue.group['serialgroup'].concurrency).to eq('2')
      # FIXME: Concurrency doesnt seem to be applied correctly, serial group should have concurrency of 1
    end
  end
  # describe '#retry_group'
end
