# spec/console_kit/doctor/reporter_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Reporter do
  let(:ok_result) do
    ConsoleKit::Doctor::Checks::Base::Result.new(
      check: 'SomeCheck', status: :ok, message: 'all good'
    )
  end

  let(:warn_result) do
    ConsoleKit::Doctor::Checks::Base::Result.new(
      check: 'SomeCheck', status: :warn, message: 'minor issue'
    )
  end

  let(:error_result) do
    ConsoleKit::Doctor::Checks::Base::Result.new(
      check: 'SomeCheck', status: :error, message: 'fatal problem'
    )
  end

  describe '#print' do
    context 'with all ok results' do
      subject(:reporter) { described_class.new([ok_result]) }

      it 'prints ok icon and message' do
        expect { reporter.print }.to output(/✓.*all good/).to_stdout
      end

      it 'prints summary with check count' do
        expect { reporter.print }.to output(/1 check\b/).to_stdout
      end
    end

    context 'with warning results' do
      subject(:reporter) { described_class.new([warn_result]) }

      it 'prints warn icon' do
        expect { reporter.print }.to output(/⚠.*minor issue/).to_stdout
      end

      it 'prints summary with warning count' do
        expect { reporter.print }.to output(/1 warning\b/).to_stdout
      end
    end

    context 'with error results' do
      subject(:reporter) { described_class.new([error_result]) }

      it 'prints error icon' do
        expect { reporter.print }.to output(/✗.*fatal problem/).to_stdout
      end

      it 'prints summary with error count' do
        expect { reporter.print }.to output(/1 error\b/).to_stdout
      end
    end

    context 'with multiple errors and warnings' do
      subject(:reporter) { described_class.new([error_result, error_result, warn_result, warn_result]) }

      it 'prints plural errors in summary' do
        expect { reporter.print }.to output(/2 errors/).to_stdout
      end

      it 'prints plural warnings in summary' do
        expect { reporter.print }.to output(/2 warnings/).to_stdout
      end
    end

    context 'with verbose: true' do
      subject(:reporter) { described_class.new([ok_result], verbose: true) }

      it 'prints the check class name' do
        expect { reporter.print }.to output(/SomeCheck/).to_stdout
      end
    end

    context 'with verbose: false (default)' do
      subject(:reporter) { described_class.new([ok_result]) }

      it 'does not print the check class name' do
        expect { reporter.print }.not_to output(/SomeCheck/).to_stdout
      end
    end

    context 'with unknown status' do
      subject(:reporter) { described_class.new([unknown_result]) }

      let(:unknown_result) do
        ConsoleKit::Doctor::Checks::Base::Result.new(
          check: 'SomeCheck', status: :unknown, message: 'strange'
        )
      end

      it 'prints a fallback icon' do
        expect { reporter.print }.to output(/\?.*strange/).to_stdout
      end
    end
  end

  describe 'Result#failure?' do
    it 'is true for error status' do
      expect(error_result.failure?).to be(true)
    end

    it 'is false for ok status' do
      expect(ok_result.failure?).to be(false)
    end
  end

  describe 'Result#warning?' do
    it 'is true for warn status' do
      expect(warn_result.warning?).to be(true)
    end

    it 'is false for ok status' do
      expect(ok_result.warning?).to be(false)
    end
  end
end
