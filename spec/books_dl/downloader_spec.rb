require 'spec_helper'
require 'tmpdir'
require 'zip'

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

  describe '#build_epub' do
    let(:downloader) { described_class.allocate }
    let(:tmpdir) { Dir.mktmpdir }
    let(:root_file) do
      instance_double(
        'BooksDL::Files::Content',
        path: 'OEBPS/content.opf',
        content: '<package/>',
        title: 'sample-book',
        export_title: 'sample-book',
        export_content: '<package/>'
      )
    end
    let(:files) do
      [
        BooksDL::BaseFile.new('mimetype', 'application/epub+zip'),
        BooksDL::BaseFile.new('META-INF/container.xml', '<container/>'),
        root_file
      ]
    end

    before do
      stub_const("#{described_class}::DOWNLOAD_DIR", tmpdir)
      downloader.instance_variable_set(:@book_id, 'book-123')
      downloader.instance_variable_set(:@book, { root_file: root_file, files: files })
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('BOOKS_DL_EPUB_LABEL').and_return(nil)
    end

    after do
      FileUtils.remove_entry(tmpdir)
    end

    it 'writes mimetype as the first uncompressed zip entry' do
      downloader.send(:build_epub)

      epub_path = File.join(tmpdir, 'book-123_sample-book.epub')

      Zip::File.open(epub_path) do |zipfile|
        first_entry = zipfile.entries.first

        expect(first_entry.name).to eq('mimetype')
        expect(first_entry.compression_method).to eq(Zip::Entry::STORED)
      end
    end

    it 'uses the export label to change the filename and root package metadata' do
      allow(ENV).to receive(:[]).with('BOOKS_DL_EPUB_LABEL').and_return('verify-cache')
      allow(root_file).to receive(:export_title).with('verify-cache').and_return('sample-book [verify-cache]')
      allow(root_file).to receive(:export_content).with('verify-cache').and_return('<package><metadata><dc:title>sample-book [verify-cache]</dc:title></metadata></package>')

      downloader.send(:build_epub)

      epub_path = File.join(tmpdir, 'book-123_sample-book [verify-cache].epub')

      Zip::File.open(epub_path) do |zipfile|
        expect(zipfile.read('OEBPS/content.opf')).to include('sample-book [verify-cache]')
      end
    end

    it 'writes a kepub filename when Kobo mode is enabled' do
      allow(ENV).to receive(:[]).with('BOOKS_DL_KOBO_KEPUB').and_return('1')

      downloader.send(:build_epub)

      kepub_path = File.join(tmpdir, 'book-123_sample-book.kepub.epub')

      expect(File.exist?(kepub_path)).to be(true)
    end
  end
end
