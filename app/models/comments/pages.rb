module Comments
  # Which student page a comment was written on, from its path alone (no query, no host): the kind of page and the
  # ids its address carries. Nothing else about a place is believed until Intake has checked it.
  module Pages
    TOPIC = /(?:ripasso|ponte|lezione)\.[a-z_]+\.[a-z0-9]+(?:-[a-z0-9]+)*/
    SKILL = /[a-z_]+\.[a-z0-9]+(?:-[a-z0-9]+)*/
    Page = Data.define(:kind, :topic, :skill, :run_id, :subject_key)

    PATTERNS = [
      [ %r{\A/today\z}, "today" ], [ %r{\A/subjects\z}, "subjects" ], [ %r{\A/settings\z}, "settings" ],
      [ %r{\A/search\z}, "search" ], [ %r{\A/comments\z}, "comments" ], [ %r{\A/diagnosis\z}, "diagnosis" ],
      [ %r{\A/diagnosis/warmup\z}, "warmup" ],
      [ %r{\A/subjects/(?<subject_key>[a-z_]+)\z}, "subject" ],
      [ %r{\A/topics/(?<topic>#{TOPIC})\z}, "topic" ],
      [ %r{\A/topics/(?<topic>#{TOPIC})/lesson\z}, "lesson" ],
      [ %r{\A/topics/(?<topic>#{TOPIC})/practice/(?<skill>#{SKILL})\z}, "practice" ],
      [ %r{\A/diagnosis/runs/(?<run_id>[1-9]\d{0,17})\z}, "sitting" ],
      [ %r{\A/diagnosis/runs/(?<run_id>[1-9]\d{0,17})/results\z}, "results" ]
    ].freeze

    # nil when the path is no page of the student.
    def self.parse(path)
      path = path.to_s
      return nil if path.length > 200

      PATTERNS.each do |pattern, kind|
        m = pattern.match(path) or next
        names = m.names
        pick = ->(name) { names.include?(name) ? m[name] : nil }
        return Page.new(kind: kind, topic: pick.("topic"), skill: pick.("skill"), run_id: pick.("run_id")&.to_i, subject_key: pick.("subject_key"))
      end
      nil
    end
  end
end
