require_relative 'helper'

options = { port: 4000 }
OptionParser.new do |opts|
  opts.banner = 'Usage: server.rb [options]'

  opts.on('-s', '--secure', 'HTTPS mode') do |v|
    options[:secure] = v
  end

  opts.on('-p', '--port [Integer]', 'listen port') do |v|
    options[:port] = v
  end

  opts.on('-u', '--push', 'Push message') do |_v|
    options[:push] = true
  end
end.parse!

puts "Starting server on port #{options[:port]}"
server = TCPServer.new(options[:port])

if options[:secure]
  ctx = OpenSSL::SSL::SSLContext.new
  ctx.cert = OpenSSL::X509::Certificate.new(File.open('keys/server.crt'))
  ctx.key = OpenSSL::PKey::RSA.new(File.open('keys/server.key'))

  ctx.ssl_version = :TLSv1_2
  ctx.options = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]
  ctx.ciphers = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:ciphers]

  ctx.alpn_protocols = ['h2']

  ctx.alpn_select_cb = lambda do |protocols|
    raise "Protocol #{DRAFT} is required" if protocols.index(DRAFT).nil?
    DRAFT
  end

  ctx.ecdh_curves = 'P-256'

  server = OpenSSL::SSL::SSLServer.new(server, ctx)
end

loop do
  sock = server.accept
  puts 'New TCP connection!'

  conn = HTTP2::Server.new
  conn.on(:frame) do |bytes|
    # puts "Writing bytes: #{bytes.unpack("H*").first}"
    sock.is_a?(TCPSocket) ? sock.sendmsg(bytes) : sock.write(bytes)
  end
  conn.on(:frame_sent) do |frame|
    puts "Sent frame: #{frame.inspect}"
  end
  conn.on(:frame_received) do |frame|
    puts "Received frame: #{frame.inspect}"
  end

  conn.on(:stream) do |stream|
    log = Logger.new(stream.id)
    req, buffer = {}, ''
    
    stream.on(:active) { log.info "client opened new stream, id: #{stream.id}" }
    stream.on(:close)  { log.info 'stream closed' }

    stream.on(:headers) do |h|
      req = Hash[*h.flatten]
      log.info "request headers: #{h}"
      log.info "capturando parametro vindo do client: #{h[5]}"
    end

    stream.on(:data) do |d|
      log.info "payload chunk: Testando trafego!!"
      buffer << d
    end

    stream.on(:half_close) do
      log.info 'client closed its end of the stream'

      response = nil
      if req[':method'] == 'POST'
        log.info "Recebido POST Request, payload: #{buffer}"
        response = "RESPONDENDO client (POST REQUEST): #{buffer}"
      else
        log.info 'Recebido GET request'
        response = 'mensagem sendo enviada do server!'
      end

      stream.headers({
        ':status' => '200',
        'content-length' => response,
        'content-type' => 'text/plain',
        'message' => '{"nome":"Michael", "idade":22}'
      }, end_stream: false)

      if options[:push]
        push_streams = []

        # send 10 promises
        10.times do |i|
          puts 'sending push'

          head = { ':method' => 'POST',
                   ':authority' => 'localhost',
                   ':scheme' => 'https',
                   ':path' => "/other_resource/#{i}" }

          stream.promise(head) do |push|
            push.headers(':status' => '200', 'content-type' => 'text/plain', 'content-length' => '11')
            push_streams << push
          end
        end
      end

      stream.data(response, end_stream: false)

      if options[:push]
        push_streams.each_with_index do |push, i|
          sleep 1
          push.data("push_data #{i}")
        end
      end
    end
  end

  while !sock.closed? && !(sock.eof? rescue true) # rubocop:disable Style/RescueModifier
    data = sock.readpartial(1024)
    # puts "Received bytes: #{data.unpack("H*").first}"

    begin
      conn << data
    rescue StandardError => e
      puts "#{e.class} exception: #{e.message} - closing socket."
      e.backtrace.each { |l| puts "\t" + l }
      sock.close
    end
  end
end

