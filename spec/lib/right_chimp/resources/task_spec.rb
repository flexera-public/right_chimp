require 'spec_helper'


class TestTasker
  SUMMARY = Struct.new(:summary)

  def show
    SUMMARY.new("TestPassState")
  end

  def href
    "tasker_href"
  end
end

describe Chimp::Task do
  let(:test_task) do
    task = Chimp::Task.new
    task.tasker = TestTasker.new
    task
  end

  describe "#wait_for_state" do
    context "with matched state" do
      subject { test_task.wait_for_state("TestPassState") }

      it { should eq(true) }
    end

    context "failed state" do
      before do
        Chimp::Connection.stub(:audit_url).and_return("audit_url")
        test_task.stub(:state).and_return("failed")
      end

      it "should raise an error with the audit link" do
        message = "FATAL error, TestPassState\n\n Audit: audit_url/audit_entries/tasker_href\n "
        expect { test_task.wait_for_state("X") }.to raise_error(message)
      end
    end

    context "timeout" do
      before do
        test_task.stub(:sleep)
        Chimp::Connection.stub(:audit_url).and_return("audit_url")
        test_task.stub(:state).and_return("pending")
      end

      it "should raise an error with the state" do
        message = "FATAL: Timeout waiting for Executable to complete.  State was pending"
        expect { test_task.wait_for_state("Timeout", 5) }.to raise_error(message)
      end
    end
  end
end
