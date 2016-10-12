require 'spec_helper'
require 'pry'

describe Chimp::ChimpDaemon do
  let(:daemon) do
    Chimp::ChimpDaemon.instance
  end

  describe '#initialize' do
    it 'is a ChimpDaemon object' do
      expect(daemon).to be_a Chimp::ChimpDaemon
    end

    it 'has a ChimpQueue object inside @queue' do
      expect(daemon.queue).to be_a Chimp::ChimpQueue
    end
  end

  describe '#run' do
    # it 'should be able to spawn a webserver'
    # it 'should be able to run forever'
    # it 'should spawn a queue runner'
    # it 'should run_forever'
  end

  describe '#parse_command_line' do
    it 'should parse all parameters' do
      string = '--logfile=/tmp/test --verbose --concurrency=34 --port=9056'
      ARGV = string.split(' ')
      daemon.parse_command_line
      expect(daemon.concurrency).to eq 34
      expect(daemon.logfile).to eq '/tmp/test'
      expect(daemon.verbose).to eq true
      expect(daemon.port).to eq '9056'
    end
  end

  describe '#spawn_webserver' do
    it 'should spawn a webserver' do
      daemon.spawn_webserver
      expect(daemon.server).to be_a WEBrick::HTTPServer
    end
  end

  describe '#run_forever' do
  end

  describe '#install_signal_handlers' do
  end

  describe '#quit' do
  end

  describe '#spawn_chimpd_submission_processor' do
  end
end
