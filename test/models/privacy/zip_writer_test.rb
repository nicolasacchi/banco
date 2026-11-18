require "test_helper"
require_relative "../../support/zip_reader"

# D-360: the zip of the student's data is written with the standard library; any unzip must read it back.
class ZipWriterTest < ActiveSupport::TestCase
  test "what is written is what is read back, names and accents included, empty files too" do
    files = { "README.txt" => "Ciao è così\n" * 200, "dati/a.json" => "[]\n", "vuoto.json" => "", "à.txt" => "x" }
    assert_equal files, ZipReader.read(Privacy::ZipWriter.build(files.to_a))
  end

  test "text is deflated and a file that does not shrink is stored" do
    big = "abc " * 5000
    zip = Privacy::ZipWriter.build([ [ "big.txt", big ], [ "tiny.txt", "x" ] ])
    assert_operator zip.bytesize, :<, big.bytesize / 4
    assert_equal({ "big.txt" => big, "tiny.txt" => "x" }, ZipReader.read(zip))
  end

  test "the stamp of the files is the time given" do
    zip = Privacy::ZipWriter.build([ [ "a", "x" ] ], time: Time.utc(2026, 11, 18, 14, 3, 6))
    local = zip.b[0, 30].unpack("VvvvvvVVVvv")
    assert_equal [ 14, 3, 6 ], [ local[4] >> 11, (local[4] >> 5) & 63, (local[4] & 31) * 2 ]
    assert_equal [ 2026, 11, 18 ], [ (local[5] >> 9) + 1980, (local[5] >> 5) & 15, local[5] & 31 ]
  end
end
