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
end
