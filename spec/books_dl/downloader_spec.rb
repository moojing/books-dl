require 'spec_helper'

RSpec.describe BooksDL::Downloader do
  describe '#file_delay_seconds' do
    let(:downloader) { described_class.allocate }

    it 'defaults to 1 second' do
      allow(ENV).to receive(:[]).with('BOOKS_DL_FILE_DELAY_SECONDS').and_return(nil)

      expect(downloader.send(:file_delay_seconds)).to eq(1.0)
    end

    it 'uses BOOKS_DL_FILE_DELAY_SECONDS when provided' do
      allow(ENV).to receive(:[]).with('BOOKS_DL_FILE_DELAY_SECONDS').and_return('1.5')

      expect(downloader.send(:file_delay_seconds)).to eq(1.5)
    end
  end

  describe '#fetch_book_content' do
    let(:api) { instance_double('BooksDL::API') }
    let(:root_file) { instance_double('BooksDL::Files::Content', file_paths: file_paths) }
    let(:file_paths) { ['OPS/ch1.xhtml', 'OPS/ch2.xhtml'] }
    let(:downloader) { described_class.allocate }

    before do
      downloader.instance_variable_set(:@api, api)
      downloader.instance_variable_set(:@book, { root_file: root_file, files: [] })
      allow(api).to receive(:fetch).and_return('<html/>')
      allow(ENV).to receive(:[]).with('BOOKS_DL_FILE_DELAY_SECONDS').and_return('1.25')
    end

    it 'sleeps between file downloads using the configured delay' do
      expect(downloader).to receive(:sleep).with(1.25).once

      downloader.send(:fetch_book_content)
    end
  end
end
