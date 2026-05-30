require 'spec_helper'

RSpec.describe BooksDL::API do
  describe '#login' do
    let(:api) { described_class.allocate }

    it 'returns immediately when already logged in' do
      expect(api.login).to be_nil
    end

    it 'does not invoke selenium browser login' do
      expect(api.login).to be_nil
    end
  end

  describe '#fetch_book_info' do
    let(:api) { described_class.allocate }
    let(:book_id) { 'E050017049_reflowable_normal' }
    let(:oauth_duplicate_response) do
      Struct.new(:body).new({ error_code: 'id_err_207', error_message: 'duplicate login' }.to_json)
    end
    let(:oauth_missing_login_uri_response) do
      Struct.new(:body).new({ error_code: 'id_err_999', error_message: 'oauth unavailable' }.to_json)
    end

    before do
      api.instance_variable_set(:@book_id, book_id)
      api.instance_variable_set(:@current_cookie, { 'CmsToken' => 'stale-token', 'DownloadToken' => 'old-download-token' })

      allow(api).to receive(:login)
      allow(api).to receive(:post)
      allow(api).to receive(:save_cookie_to_file)
    end

    it 'raises a descriptive error when oauth response does not include login_uri after retry' do
      allow(api).to receive(:get).and_return(oauth_duplicate_response, oauth_missing_login_uri_response)

      expect { api.send(:fetch_book_info) }
        .to raise_error(RuntimeError, /取得 OAuth login URI 失敗.*id_err_999.*oauth unavailable/m)
    end
  end
end
