require "zlib"

module Privacy
  # A zip file written with the standard library only (Zlib), for the student's data export (D-360): no gem, no temp file. Every
  # entry is deflated (stored when that is not smaller), names are UTF-8, there is no zip64 (the export is far below 4 GB) and no
  # encryption. Any unzip program reads it.
  module ZipWriter
    LOCAL = 0x04034b50
    CENTRAL = 0x02014b50
    END_OF_CENTRAL = 0x06054b50
    UTF8_NAMES = 0x0800
    VERSION = 20
    LIMIT = 0xFFFF_FFFF

    module_function

    # entries: [[name, content]] in order; the result is the zip as a binary String. `time` is the files' time (UTC, 1980..2107).
    def build(entries, time: Time.now)
      stamp = time.utc
      dos_time = (stamp.hour << 11) | (stamp.min << 5) | (stamp.sec / 2)
      dos_date = ((stamp.year - 1980) << 9) | (stamp.month << 5) | stamp.day
      body = String.new(encoding: Encoding::BINARY)
      directory = String.new(encoding: Encoding::BINARY)
      entries.each do |name, content|
        data = content.to_s.b
        name = name.to_s.b
        crc = Zlib.crc32(data)
        packed, method = compress(data)
        raise ArgumentError, "zip64 is not supported (#{name})" if data.bytesize > LIMIT || body.bytesize > LIMIT
        offset = body.bytesize
        body << [ LOCAL, VERSION, UTF8_NAMES, method, dos_time, dos_date, crc, packed.bytesize, data.bytesize, name.bytesize, 0 ].pack("VvvvvvVVVvv") << name << packed
        directory << [ CENTRAL, VERSION, VERSION, UTF8_NAMES, method, dos_time, dos_date, crc, packed.bytesize, data.bytesize,
                       name.bytesize, 0, 0, 0, 0, 0, offset ].pack("VvvvvvvVVVvvvvvVV") << name
      end
      end_record = [ END_OF_CENTRAL, 0, 0, entries.size, entries.size, directory.bytesize, body.bytesize, 0 ].pack("VvvvvVVv")
      body << directory << end_record
    end

    # [bytes, method]: method 8 (deflate) unless the raw bytes are not larger, then 0 (stored).
    def compress(data)
      deflater = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
      packed = deflater.deflate(data, Zlib::FINISH)
      deflater.close
      packed.bytesize < data.bytesize ? [ packed, 8 ] : [ data, 0 ]
    end
  end
end
