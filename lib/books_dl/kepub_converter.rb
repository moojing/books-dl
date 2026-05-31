require 'nokogiri'

module BooksDL
  class KepubConverter
    XHTML_MIME = 'application/xhtml+xml'
    SKIP_TAGS = %w[script style head title].freeze

    def initialize(files, root_file)
      @files = files
      @root_file = root_file
    end

    def convert
      spine_index_map = build_spine_index_map

      @files.map do |file|
        spine_index = spine_index_map[file.path]
        next file unless spine_index

        converted = process_xhtml(file.content, spine_index)
        converted ? BaseFile.new(file.path, converted) : file
      end
    end

    private

    def build_spine_index_map
      doc = Nokogiri::XML(@root_file.content)
      doc.remove_namespaces!

      href_by_id = {}
      doc.css('manifest item').each do |item|
        next unless item['media-type'] == XHTML_MIME

        href_by_id[item['id']] = item['href']
      end

      base = File.dirname(@root_file.path)
      index = {}
      doc.css('spine itemref').each_with_index do |itemref, i|
        href = href_by_id[itemref['idref']]
        next unless href

        index[File.join(base, href)] = i + 1
      end
      index
    end

    def process_xhtml(content, spine_index)
      doc = Nokogiri::XML(content)
      xhtml_ns = doc.root&.namespace

      text_nodes = collect_text_nodes(doc)
      return nil if text_nodes.empty?

      text_nodes.each_with_index do |node, i|
        span = doc.create_element('span')
        span.namespace = xhtml_ns if xhtml_ns
        span['class'] = 'koboSpan'
        span['id'] = "kobo.#{spine_index}.#{i + 1}"
        node.add_next_sibling(span)
        span.add_child(node)
      end

      doc.to_xml
    end

    def collect_text_nodes(doc)
      nodes = []
      doc.traverse do |node|
        next unless node.is_a?(Nokogiri::XML::Text)
        next if node.content.strip.empty?
        next if SKIP_TAGS.include?(node.parent&.name&.downcase)

        nodes << node
      end
      nodes
    end
  end
end
