module BooksDL
  class API
    attr_reader :current_cookie, :book_id, :encoded_token

    COOKIE_FILE_NAME = 'cookie.json'.freeze
    IMAGE_EXTENSIONS = %w[.bmp .gif .ico .jpeg .jpg .tiff .tif .svg .png .webp].freeze
    NO_AUTH_EXTENSIONS = %w[.css .ttc .otf .ttf .eot .woff .woff2].freeze

    # API ENDPOINTS
    #
    # rubocop:disable Metrics/LineLength
    DEVICE_REG_URL = 'https://appapi-ebook.books.com.tw/V1.7/CMSAPIApp/DeviceReg'.freeze
    OAUTH_URL = 'https://appapi-ebook.books.com.tw/V1.7/CMSAPIApp/LoginURL?type=&device_id=&redirect_uri=https%3A%2F%2Fviewer-ebook.books.com.tw%2Fviewer%2Flogin.html'.freeze
    OAUTH_ENDPOINT_URL = 'https://appapi-ebook.books.com.tw/V1.7/CMSAPIApp/MemberLogin?code='.freeze
    BOOK_DL_URL = 'https://appapi-ebook.books.com.tw/V1.7/CMSAPIApp/BookDownLoadURL'.freeze
    # rubocop:enable Metrics/LineLength

    def initialize(book_id)
      @book_id = book_id
      load_existed_cookies
      fetch_info
    end

    def switch_book(new_book_id)
      @book_id = new_book_id
      @info = nil
      @encoded_token = nil

      resp = get("#{BOOK_DL_URL}?book_uni_id=#{@book_id}&t=#{Time.now.to_i}")
      parsed = JSON.parse(resp.body.to_s)

      if parsed['error_code']
        raise "BookDownLoadURL 失敗：#{parsed['error_message']}，請重新執行程式。"
      end

      @info = OpenStruct.new(parsed)
      @encoded_token = CGI.escape(@info.download_token.to_s)
    end

    def fetch(path)
      url = "#{info.download_link}#{path}"
      ext = File.extname(path).downcase

      if NO_AUTH_EXTENSIONS.include?(ext) || info.encrypt_type == 'none'
        get(url).body.to_s
      elsif IMAGE_EXTENSIONS.include?(ext)
        checksum = Utils.img_checksum
        resp = get("#{url}?checksum=#{checksum}&DownloadToken=#{encoded_token}")

        resp.body.to_s
      else
        key = Utils.generate_key(url, info.download_token)
        resp = get("#{url}?DownloadToken=#{encoded_token}")

        Utils.decode_xor(key, resp.body.to_s)
      end
    end

    def fetch_info
      @info = fetch_book_info
      @encoded_token = CGI.escape(@info.download_token.to_s)
    end

    # return Struct of [:book_uni_id, :download_link, :download_token, :size, :encrypt_type]
    def info
      @info
    end

    private def fetch_book_info
      begin
        login

        data = {
          form: {
            device_id: '2b2475e7-da58-4cfe-aedf-ab4e6463757b',
            language: 'zh-TW',
            os_type: 'WEB',
            os_version: default_headers[:'user-agent'],
            screen_resolution: '1680X1050',
            screen_dpi: 96,
            device_vendor: 'Google Inc.',
            device_model: 'web'
          }
        }

        headers = {
          accept: 'application/json, text/javascript, */*; q=0.01',
          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
          Origin: 'https://viewer-ebook.books.com.tw',
          Referer: 'https://viewer-ebook.books.com.tw/viewer/epub/web/?book_uni_id=E050017049_reflowable_normal',
        }

        # remove old DownloadToken but keep CmsToken if exists
        current_cookie.reject! { |key| %w[redirect_uri normal_redirect_uri DownloadToken].include?(key) }
        puts '註冊 Fake device 中...'
        post(DEVICE_REG_URL, data, headers)

        puts '透過 OAuth 取得 CmsToken...'
        resp = get(OAUTH_URL)
        parsed_oauth = JSON.parse(resp.body.to_s)

        # 如果是重複登入錯誤，清掉舊 CmsToken 重試一次
        if parsed_oauth['error_code'] == 'id_err_207'
          puts '偵測到重複登入，清除舊 session 重試...'
          current_cookie.delete('CmsToken')
          current_cookie.delete('cmsToken')
          save_cookie_to_file
          resp = get(OAUTH_URL)
          parsed_oauth = JSON.parse(resp.body.to_s)
        end

        login_uri = extract_login_uri(parsed_oauth)
        puts "\n請在 Chrome 瀏覽器中開啟以下網址："
        puts login_uri
        puts "\n⚠️  網址會自動跳轉到 login.html?...&code=XXXXX 的網址"
        puts "    請複製那個含有 code= 的網址貼到這裡按 Enter："
        redirect_url = $stdin.gets&.chomp
        code = redirect_url&.split('&code=')&.last&.split('&')&.first
        code ||= redirect_url&.split('?code=')&.last&.split('&')&.first
        raise "無法取得 OAuth code，請確認網址含有 code= 參數。你貼的是：#{redirect_url}" if code.nil? || code.empty? || code.start_with?('http')
        oauth_resp = get("#{OAUTH_ENDPOINT_URL}#{code}")

        resp = get("#{BOOK_DL_URL}?book_uni_id=#{book_id}&t=#{Time.now.to_i}")
        parsed = JSON.parse(resp.body.to_s)

        if parsed['error_code']
          raise "BookDownLoadURL 失敗：#{parsed['error_message']}，請重新執行程式。"
        end

        OpenStruct.new(parsed)
      end
    end

    public

    def login
      nil
    end

    private

    def load_existed_cookies
      data = JSON.parse(File.read(COOKIE_FILE_NAME))
      # 支援 Cookie-Editor 匯出的陣列格式
      if data.is_a?(Array)
        @current_cookie = data.each_with_object({}) { |c, h| h[c['name']] = c['value'] }
      else
        @current_cookie = data
      end
    rescue StandardError
      @current_cookie = {}
    end

    def save_cookie_to_file
      File.open(COOKIE_FILE_NAME, 'w') { |f| f.write(JSON.pretty_generate(current_cookie)) }
    end

    def get(url, headers = {})
      headers = build_headers({ Cookie: cookie }, headers)
      response = HTTP.headers(headers).get(url)

      if response.status >= 400
        file_name = URI(url).path.split('/').last
        raise "取得 `#{file_name}` 失敗。 Status: #{response.status}"
      end

      save_cookie(response)
      response
    end

    def post(url, data = {}, headers = {})
      headers = build_headers({ Cookie: cookie }, headers)
      response = HTTP.headers(headers).post(url, **data)
      save_cookie(response)

      response
    end

    def save_cookie(response)
      cookie_jar = response.cookies
      cookie_hash = cookie_jar.map { |cookie| [cookie.name, cookie.value] }.to_h
      current_cookie.merge!(cookie_hash)

      cookie_json = JSON.pretty_generate(current_cookie)
      File.open(COOKIE_FILE_NAME, 'w') do |file|
        file.write(cookie_json)
      end
    end

    def cookie
      current_cookie.reduce('') { |cookie, (name, value)| cookie + "#{name}=#{value}; " }.strip
    end

    def default_headers
      @default_headers ||= {
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' \
                      'AppleWebKit/537.36 (KHTML, like Gecko) ' \
                      'Chrome/124.0.0.0 Safari/537.36'
      }
    end

    def build_headers(*args)
      args.reduce(default_headers, &:merge)
    end

    def extract_login_uri(parsed_oauth)
      login_uri = parsed_oauth['login_uri']
      return login_uri unless login_uri.nil? || login_uri.empty?

      error_code = parsed_oauth['error_code']
      error_message = parsed_oauth['error_message']
      response_body = JSON.generate(parsed_oauth)

      if error_code || error_message
        raise "取得 OAuth login URI 失敗：#{error_code} #{error_message}。原始回應：#{response_body}".strip
      end

      raise "取得 OAuth login URI 失敗：API 回應缺少 login_uri。原始回應：#{response_body}"
    end

  end
end
