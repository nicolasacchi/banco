# The tests of the reserved dry run and of the availability registry need a piece that is held back. Every track of wave 2 makes its pieces
# available in the commit of its look gate, so a test cannot name a piece that stays reserved: it holds one back for the length of a block
# (the registry's entries are plain hashes, restored afterwards; each test process has its own copy).
module ReservedPiece
  def with_reserved(kind, name, status: "reserved")
    entry = Lessons::Types.entry(kind, name)
    was = entry["status"]
    entry["status"] = status
    yield
  ensure
    entry["status"] = was
  end
end
