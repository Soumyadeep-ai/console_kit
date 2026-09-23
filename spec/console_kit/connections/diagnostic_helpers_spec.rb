# frozen_string_literal: true

RSpec.describe ConsoleKit::Connections::DiagnosticHelpers do
  describe '.scrub' do
    leaking = {
      'a connection URL' => ['cannot reach redis://user:hunter2@cache.internal:6379/2', 'hunter2'],
      'a quoted hash assignment' => ['cfg={"host"=>"db.internal","password"=>"hunter2"}', 'hunter2'],
      'a PostgreSQL auth failure' => ['FATAL: password authentication failed for user "svc_admin"', 'svc_admin'],
      'a space-separated password' => ['authentication failed for user admin with password hunter2', 'hunter2'],
      'a Redis WRONGPASS reply' => ['WRONGPASS invalid username-password pair for user default', 'default'],
      'a Mongo principal' => ['Mongo::Auth::Unauthorized: User svc_admin@admin is not authorized', 'svc_admin']
    }

    leaking.each do |label, (message, secret)|
      it "redacts the secret in #{label}" do
        expect(described_class.scrub(message)).not_to include(secret)
      end
    end

    it 'keeps the error class of a Mongo authorization failure' do
      message = 'Mongo::Auth::Unauthorized: User svc_admin@admin is not authorized'
      expect(described_class.scrub(message)).to include('Mongo::Auth::Unauthorized')
    end

    it 'keeps a message that carries no credential at all' do
      message = 'PG::ConnectionBad: could not connect to server'
      expect(described_class.scrub(message)).to eq(message)
    end

    it 'keeps a host and port, which are not secrets' do
      message = 'Redis::CannotConnectError: Error connecting to Redis on localhost:6379'
      expect(described_class.scrub(message)).to include('localhost:6379')
    end

    it 'keeps the reason in a PostgreSQL auth failure' do
      message = 'FATAL: password authentication failed for user "svc_admin"'
      expect(described_class.scrub(message)).to include('authentication failed')
    end

    it 'handles a nil message' do
      expect(described_class.scrub(nil)).to eq('')
    end

    it 'redacts in a single scan, so a later shape cannot re-match an earlier redaction' do
      message = 'for user hunter2=password extra'
      expect(described_class.scrub(message)).to eq('[redacted] extra')
    end

    it 'is idempotent' do
      message = 'authentication failed for user admin with password hunter2'
      expect(described_class.scrub(described_class.scrub(message))).to eq(described_class.scrub(message))
    end

    context 'with an auth header' do
      it 'redacts a bearer token' do
        message = 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def'
        expect(described_class.scrub(message)).not_to include('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9')
      end

      it 'redacts basic credentials' do
        expect(described_class.scrub('api_key: Basic YWRtaW46aHVudGVyMg==')).not_to include('YWRtaW46aHVudGVyMg==')
      end

      it 'redacts a token scheme value' do
        expect(described_class.scrub('authorization = Token s3cr3tvalue')).not_to include('s3cr3tvalue')
      end
    end

    context 'with a message that is not valid UTF-8' do
      let(:invalid) { "connection failed \xC3(".dup.force_encoding('UTF-8') }

      it 'does not raise' do
        expect { described_class.scrub(invalid) }.not_to raise_error
      end

      it 'keeps the readable part' do
        expect(described_class.scrub(invalid)).to include('connection failed')
      end
    end

    context 'with ordinary words that merely look like secrets' do
      it 'keeps a token limit message' do
        expect(described_class.scrub('token limit exceeded for index')).to eq('token limit exceeded for index')
      end

      it 'keeps an auth type message' do
        expect(described_class.scrub('auth type not supported')).to eq('auth type not supported')
      end
    end
  end
end
