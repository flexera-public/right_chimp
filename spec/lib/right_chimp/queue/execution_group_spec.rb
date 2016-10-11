require 'spec_helper'

describe Chimp::ExecutionGroupFactory do
  describe ".from_type" do
    context "serial" do
      subject { Chimp::ExecutionGroupFactory.from_type(:serial) }

      it "returns a SerialExecutionGroup" do
        should be_a_kind_of(Chimp::SerialExecutionGroup)
      end
    end

    context "parallel" do
      subject { Chimp::ExecutionGroupFactory.from_type(:parallel) }

      it "returns a ParallelExecutionGroup" do
        should be_a_kind_of(Chimp::ParallelExecutionGroup)
      end
    end

    context "invalid" do
      it "raises an error" do
        expect { Chimp::ExecutionGroupFactory.from_type(:bad_type) }.to raise_error
      end
    end
  end
end
