# The raw text of an answer sent as JSON, as the stored attempts have it: plain text as is, structured answers as JSON, a testlet's answers one text
# per sub item (the blind solve and the read-only grade command grade what the reviewer sends the way the student's page sends it).
module RawAnswer
  private

  def raw_answer(value, testlet: false)
    if testlet && value.is_a?(Hash)
      JSON.generate(value.transform_values { |v| v.is_a?(String) ? v : JSON.generate(v) })
    elsif value.is_a?(String) then value
    else JSON.generate(value)
    end
  end
end
