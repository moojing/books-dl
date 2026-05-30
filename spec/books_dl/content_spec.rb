require 'spec_helper'

RSpec.describe BooksDL::Files::Content do
  let(:path) { 'OEBPS/content.opf' }
  let(:content) { file_fixture('content.opf').read }
  let(:root_file) { described_class.new(path, content) }

  describe '#export_title' do
    it 'returns the original title when no label is provided' do
      expect(root_file.export_title(nil)).to eq('迷霧之子—執法鎔金：自影')
    end

    it 'appends the label to the title when provided' do
      expect(root_file.export_title('verify-cache')).to eq('迷霧之子—執法鎔金：自影 [verify-cache]')
    end
  end

  describe '#export_content' do
    it 'preserves the original metadata when no label is provided' do
      expect(root_file.export_content(nil)).to eq(content)
    end

    it 'updates the package title and identifier when a label is provided' do
      exported = Nokogiri::XML(root_file.export_content('verify-cache'))

      title = exported.at_xpath('//dc:title', 'dc' => 'http://purl.org/dc/elements/1.1/').text
      identifier = exported.at_xpath('//dc:identifier', 'dc' => 'http://purl.org/dc/elements/1.1/').text

      expect(title).to eq('迷霧之子—執法鎔金：自影 [verify-cache]')
      expect(identifier).to eq('布蘭登．山德森(Brandon Sanderson) [verify-cache]')
    end
  end
end
