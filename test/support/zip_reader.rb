require "zlib"

# Reads a zip back (the central directory, then each entry), so the tests see the bytes a student's unzip would see: { name => UTF-8 text }.
# It checks the signature, the size and the CRC of every entry and raises on anything else.
module ZipReader
  CENTRAL = 0x02014b50

  module_function

  def read(bytes)
    bytes = bytes.b
    end_record = bytes.rindex([ 0x06054b50 ].pack("V")) or raise "no end of central directory"
    total, _size, offset = bytes[end_record, 22].unpack("VvvvvVV").values_at(3, 5, 6)
    position = offset
    entries = {}
    total.times do
      sig, _made, _need, flags, method, _time, _date, crc, packed_size, size, name_size, extra_size, comment_size, _disk, _internal, _external, local =
        bytes[position, 46].unpack("VvvvvvvVVVvvvvvVV")
      raise "bad central entry" unless sig == CENTRAL
      raise "names are not flagged UTF-8" unless flags & 0x0800 == 0x0800

      name = bytes[position + 46, name_size].force_encoding(Encoding::UTF_8)
      local_name_size, local_extra_size = bytes[local + 26, 4].unpack("vv")
      packed = bytes[local + 30 + local_name_size + local_extra_size, packed_size]
      data = method == 8 ? Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(packed) : packed
      raise "#{name}: wrong size" unless data.bytesize == size
      raise "#{name}: wrong crc" unless Zlib.crc32(data) == crc

      entries[name] = data.force_encoding(Encoding::UTF_8)
      position += 46 + name_size + extra_size + comment_size
    end
    entries
  end
end
