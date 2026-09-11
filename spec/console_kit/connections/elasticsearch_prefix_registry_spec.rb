# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::ElasticsearchPrefixRegistry do
  # elasticsearch-model is optional, and not every version that is loaded
  # exposes `index_name_prefix`. The registry feature-detects both the reader
  # and the writer rather than sniffing a version, so these are the library
  # shapes those guards exist for.
  describe 'a library that cannot carry a process-wide prefix' do
    context 'when elasticsearch-model is not loaded at all' do
      before { hide_const('Elasticsearch::Model') }

      it 'resolves no model' do
        expect(described_class.model).to be_nil
      end

      it 'reports no global prefix instead of raising on nil' do
        expect(described_class.global).to be_nil
      end

      it 'is not settable' do
        expect(described_class).not_to be_settable
      end

      it 'is not readable' do
        expect(described_class).not_to be_readable
      end
    end

    context 'when the loaded version exposes no index_name_prefix' do
      before { stub_const('Elasticsearch::Model', Elasticsearch::ModelWithoutPrefix) }

      it 'is not readable' do
        expect(described_class).not_to be_readable
      end

      it 'reports no global prefix' do
        expect(described_class.global).to be_nil
      end

      it 'drops a write rather than raising NoMethodError' do
        expect { described_class.global = nil }.not_to raise_error
      end
    end
  end
end
