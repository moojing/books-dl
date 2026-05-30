require 'zip'

module BooksDL
  class Downloader
    DOWNLOAD_DIR = 'downloads'.freeze

    attr_reader :api, :book, :book_id, :info

    def initialize(book_id, api: nil)
      @book_id = book_id
      if api
        @api = api
        @api.switch_book(book_id)
      else
        @api = API.new(book_id)
      end
      @book = {
        root_file_path: nil,
        root_file: nil,
        files: [
          ::BooksDL::BaseFile.new('mimetype', 'application/epub+zip')
        ]
      }
    end

    def perform
      Dir.mkdir(DOWNLOAD_DIR) unless Dir.exist?(DOWNLOAD_DIR)

      if already_downloaded?
        puts "#{book_id} 已下載過，跳過。"
        return
      end

      job('取得 META-INF/container.xml') { fetch_container_file }
      job('取得 META-INF/encryption.xml') { fetch_encryption_file }
      job("取得 #{book[:root_file_path]} 檔案") { fetch_root_file }
      fetch_book_content # 由內部顯示 job 訊息
      job('製作 epub 檔案') { build_epub }

      puts "#{book_id} 下載完成"
    end

    private

    def job(name)
      print "正在#{name}..."
      puts '成功' if yield
    end

    def fetch_container_file
      path = 'META-INF/container.xml'
      content = api.fetch(path)
      container_file = Files::Container.new(path, content)

      book[:root_file_path] = container_file.root_file_path
      book[:files] << container_file
    end

    def fetch_encryption_file
      path = 'META-INF/encryption.xml'
      content = api.fetch(path)
      encryption_file = BaseFile.new(path, content)

      book[:files] << encryption_file
    rescue StandardError => e
      puts "\n#{e}"
      puts "Just a encryption file, it doesn't matter..."

      false
    end

    def fetch_root_file
      path = book[:root_file_path]
      content = api.fetch(path)
      root_file = Files::Content.new(path, content)

      book[:root_file] = root_file
      book[:files] << root_file
    end

    def fetch_book_content
      root_file = book[:root_file]
      file_paths = root_file.file_paths

      total = file_paths.size
      file_paths.each_with_index do |path, index|
        puts "#{index + 1}/#{total} => 開始下載 #{path}"
        content = api.fetch(path)

        book[:files] << BaseFile.new(path, content)
        sleep(file_delay_seconds) if index < total - 1
      end
    end

    def file_delay_seconds
      env_seconds('BOOKS_DL_FILE_DELAY_SECONDS', default: 1.0)
    end

    def env_seconds(key, default:)
      raw = ENV[key]
      return default if raw.nil? || raw.empty?

      Float(raw)
    rescue ArgumentError
      default
    end

    def already_downloaded?
      Dir.glob("#{DOWNLOAD_DIR}/#{book_id}_*.epub").any?
    end

    def build_epub
      label = export_label
      title = book[:root_file].export_title(label)
      files = book[:files]
      filename = File.join(DOWNLOAD_DIR, "#{book_id}_#{title}#{output_extension}")

      ::Zip::File.open(filename, create: true) do |zipfile|
        files.each do |file|
          options = if file.path == 'mimetype'
                      { compression_method: ::Zip::Entry::STORED }
                    else
                      {}
                    end

          file_content = if file.equal?(book[:root_file])
                           book[:root_file].export_content(label)
                         else
                           file.content
                         end

          zipfile.get_output_stream(file.path, **options) { |zip| zip.write(file_content) }
        end
      end
    end

    def export_label
      ENV['BOOKS_DL_EPUB_LABEL']
    end

    def output_extension
      ENV['BOOKS_DL_KOBO_KEPUB'] == '1' ? '.kepub.epub' : '.epub'
    end
  end
end
