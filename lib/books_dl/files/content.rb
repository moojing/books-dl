module BooksDL
  module Files
    class Content < ::BooksDL::BaseFile
      DC_NAMESPACE = { 'dc' => 'http://purl.org/dc/elements/1.1/' }.freeze

      def file_paths
        doc.css('item').map do |item|
          ::File.join(base_dir, item.attr('href')).to_s
        end
      end

      def title
        doc.remove_namespaces!
           .css('title')
           .first
           .text
      end

      def export_title(label)
        return title if label.nil? || label.empty?

        append_label(title, label)
      end

      def export_content(label)
        return content if label.nil? || label.empty?

        exported_doc = Nokogiri::XML(content)
        title_node = exported_doc.at_xpath('//dc:title', DC_NAMESPACE)
        identifier_node = exported_doc.at_xpath('//dc:identifier', DC_NAMESPACE)

        title_node.content = append_label(title_node.text, label) if title_node
        identifier_node.content = append_label(identifier_node.text, label) if identifier_node

        exported_doc.to_xml
      end

      private

      # OEBPS/content.opf => OEBPS
      def base_dir
        ::File.dirname(path)
      end

      def doc
        Nokogiri::XML(content)
      end

      def append_label(value, label)
        "#{value} [#{label}]"
      end
    end
  end
end
