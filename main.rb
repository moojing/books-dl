require_relative './lib/books_dl'


# 如何取得 book_id
# 進入你要下載的書的閱讀頁面，取得網址列中網址
# 例如：
#   https://viewer-ebook.books.com.tw/viewer/epub/web/?book_uni_id=E050096232_reflowable_normal&ran=97991701
# book_uni_id= 之後的字串就是這本書的 book_id 了
#
book_ids = [
  'E050127971_reflowable_normal',
  'E050054921_reflowable_normal'
]

# 過濾已下載的書，避免不必要的登入流程
pending_ids = book_ids.reject do |id|
  Dir.glob("#{BooksDL::Downloader::DOWNLOAD_DIR}/#{id}_*.epub").any?
end

if pending_ids.empty?
  puts "所有書籍都已下載完成。"
  exit
end

shared_api = nil

def env_seconds(key, default:)
  raw = ENV[key]
  return default if raw.nil? || raw.empty?

  Float(raw)
rescue ArgumentError
  default
end

book_delay_seconds = env_seconds('BOOKS_DL_BOOK_DELAY_SECONDS', default: 5.0)

pending_ids.each_with_index do |book_id, index|
  if shared_api
    downloader = BooksDL::Downloader.new(book_id, api: shared_api)
  else
    downloader = BooksDL::Downloader.new(book_id)
    shared_api = downloader.api
  end
  downloader.perform
  sleep(book_delay_seconds) if index < pending_ids.size - 1
end
