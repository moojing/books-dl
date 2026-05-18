require 'spec_helper'

RSpec.describe BooksDL::API do
  describe '#login' do
    let(:api) { described_class.allocate }

    before do
      allow(api).to receive(:logged?).and_return(false)
    end

    it 'raises when browser login fails instead of falling back to manual captcha login' do
      allow(api).to receive(:login_with_slider_captcha).and_return(false)

      expect(api).not_to receive(:post)

      expect { api.login }
        .to raise_error(RuntimeError, /瀏覽器登入失敗|browser login failed/i)
    end
  end
end
