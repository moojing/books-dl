require 'spec_helper'

RSpec.describe BooksDL::KepubConverter do
  XHTML_NS = 'http://www.w3.org/1999/xhtml'

  let(:opf_content) { file_fixture('kepub_content.opf').read }
  let(:root_file) { BooksDL::Files::Content.new('OEBPS/content.opf', opf_content) }

  # spine positions from kepub_content.opf:
  #   cover.xhtml => 1, ch1.xhtml => 2, ch2.xhtml => 3, ch3.xhtml => 4
  let(:cover_file) { BooksDL::BaseFile.new('OEBPS/cover.xhtml', file_fixture('cover_svg.xhtml').read) }
  let(:ch1_file)   { BooksDL::BaseFile.new('OEBPS/ch1.xhtml',   file_fixture('chapter_simple.xhtml').read) }
  let(:ch2_file)   { BooksDL::BaseFile.new('OEBPS/ch2.xhtml',   file_fixture('chapter_mixed.xhtml').read) }
  let(:ch3_file)   { BooksDL::BaseFile.new('OEBPS/ch3.xhtml',   file_fixture('chapter_with_style.xhtml').read) }
  let(:css_file)   { BooksDL::BaseFile.new('OEBPS/css/styles.css', 'body {}') }
  let(:mime_file)  { BooksDL::BaseFile.new('mimetype', 'application/epub+zip') }

  let(:files) { [mime_file, root_file, cover_file, ch1_file, ch2_file, ch3_file, css_file] }

  subject(:result) { described_class.new(files, root_file).convert }

  def converted_doc(path)
    file = result.find { |f| f.path == path }
    Nokogiri::XML(file.content)
  end

  def kobo_spans(doc)
    doc.xpath('//*[@class="koboSpan"]')
  end

  # --- Issue 1: namespace pollution ---

  describe 'injected span namespace' do
    it 'does not add xmlns="" to koboSpan elements' do
      doc = converted_doc('OEBPS/ch1.xhtml')

      kobo_spans(doc).each do |span|
        expect(span.namespace&.href).to eq(XHTML_NS)
      end
    end
  end

  # --- Issue 2: SVG-only page returned unchanged ---

  describe 'SVG-only page' do
    it 'returns the original file object when there are no wrappable text nodes' do
      converted_cover = result.find { |f| f.path == 'OEBPS/cover.xhtml' }

      expect(converted_cover).to equal(cover_file)
    end
  end

  # --- Issue 3: mixed content — all text nodes wrapped with sequential IDs ---

  describe 'mixed content chapter (ch2, spine index 3)' do
    it 'wraps every text node including those inside inline elements' do
      doc = converted_doc('OEBPS/ch2.xhtml')
      ids = kobo_spans(doc).map { |s| s['id'] }

      # <p>before <span class="x">inside</span> after</p>  => 3 nodes
      # <h4><span class="case">方法１</span>小時候的記憶</h4> => 2 nodes
      expect(ids).to eq(%w[kobo.3.1 kobo.3.2 kobo.3.3 kobo.3.4 kobo.3.5])
    end

    it 'keeps wrapped text content intact' do
      doc = converted_doc('OEBPS/ch2.xhtml')
      texts = kobo_spans(doc).map(&:text)

      expect(texts).to eq(['before ', 'inside', ' after', '方法１', '小時候的記憶'])
    end
  end

  # --- Issue 4: <style> and <script> content not wrapped ---

  describe 'chapter with inline CSS (ch3, spine index 4)' do
    it 'does not wrap text inside <style> tags' do
      doc = converted_doc('OEBPS/ch3.xhtml')
      style_node = doc.at_css('style')

      expect(style_node.xpath('.//*[@class="koboSpan"]')).to be_empty
      expect(style_node.text).to include('margin: 0')
    end

    it 'wraps body text nodes and assigns the correct spine-indexed ID' do
      doc = converted_doc('OEBPS/ch3.xhtml')
      ids = kobo_spans(doc).map { |s| s['id'] }

      expect(ids).to eq(['kobo.4.1'])
      expect(kobo_spans(doc).first.text).to eq('正文段落。')
    end
  end

  # --- simple chapter correctness (ch1, spine index 2) ---

  describe 'simple chapter (ch1, spine index 2)' do
    it 'wraps paragraph text with sequential IDs starting at the spine index' do
      doc = converted_doc('OEBPS/ch1.xhtml')
      ids = kobo_spans(doc).map { |s| s['id'] }

      expect(ids).to eq(%w[kobo.2.1 kobo.2.2])
    end
  end

  # --- non-spine files pass through untouched ---

  describe 'non-spine files' do
    it 'returns mimetype and CSS files as the original objects' do
      expect(result.find { |f| f.path == 'mimetype' }).to equal(mime_file)
      expect(result.find { |f| f.path == 'OEBPS/css/styles.css' }).to equal(css_file)
    end
  end
end
