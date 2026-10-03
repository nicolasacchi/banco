module Teacher
  # The teacher's time, measured (C-04). The pages send a beat while they are visible
  # and in use; the server keeps one app_event teacher_active per minute at most, with
  # the unit of the page ("math:graph", "math:test", "math:report", "evening", "home").
  # One event is one minute. `banco status` reports the totals per unit and per subject,
  # from which the opening date is worked out.
  module Minutes
    KIND = "teacher_active".freeze
    MIN_GAP = 55 # seconds: a beat that comes sooner is not another minute
    UNIT = /\A(?:[a-z_]+:(?:graph|test|report)|evening|home)\z/

    module_function

    # Returns true when the minute was recorded.
    def record(unit, now: Time.current)
      return false unless unit.to_s.match?(UNIT)

      subject = unit.split(":").first
      return false if unit.include?(":") && !Subject.exists?(key: subject)

      last = AppEvent.where(kind: KIND).order(:id).last
      return false if last && now - last.created_at < MIN_GAP

      AppEvent.create!(kind: KIND, payload_json: { unit: unit }.to_json, created_at: now)
      true
    end

    # {total:, by_unit: {"math:graph" => 12}, by_subject: {"math" => 30}}
    def summary
      by_unit = AppEvent.where(kind: KIND).pluck(:payload_json).map { |j| JSON.parse(j)["unit"] }.tally.sort.to_h
      by_subject = by_unit.each_with_object(Hash.new(0)) { |(unit, n), h| h[unit.split(":").first] += n if unit.include?(":") }
      { total: by_unit.values.sum, by_unit: by_unit, by_subject: by_subject.sort.to_h }
    end
  end
end
