module Search
  # Where a hit leads: the pages that already exist. A hit never opens anything the page itself would not.
  module Links
    module_function

    # A student's page: a lesson card opens the lesson at its card, a glossary term the card that teaches it (or the lesson), a topic
    # its page, an exercise the topic's practice page for its skill (the practice selector still chooses what is served: the link
    # never carries an instance). +targets+: Scope::Student#practice_targets.
    def student(hit, targets)
      case hit.kind
      when "lesson_card", "glossary_term" then "/topics/#{hit.topic_key}/lesson#{"##{hit.anchor}" if hit.anchor.present?}"
      when "topic" then "/topics/#{hit.key}"
      when "practice_item"
        topic, skill = targets[hit.revision_id]
        topic ? "/topics/#{topic}/practice/#{skill}" : nil
      end
    end

    # The teacher's page for a hit (path); nil where there is no page of its own (a reference article or a programme line is read in
    # the result itself).
    def staff(hit)
      subject = hit.subject
      case hit.kind
      when "topic", "lesson_card", "glossary_term"
        "/teacher/subjects/#{subject}/topics/#{hit.topic_key || hit.key}#{"##{hit.anchor}" if hit.anchor.present?}"
      when "course" then "/teacher/subjects/#{subject}/course"
      when "skill" then "/teacher/subjects/#{subject}/test/skills/#{hit.key}"
      when "item", "item_instance", "practice_item", "finding" then hit.revision_id ? "/teacher/items/#{hit.revision_id}" : nil
      when "student_answer" then "/teacher/subjects/#{subject}/report"
      end
    end

    # A short address an agent can follow with the CLI: "topic:KEY", "item:KEY#seed", "reference:KEY#art-3".
    def address(hit) = "#{hit.kind}:#{hit.key}#{"##{hit.anchor}" if hit.anchor.present?}"
  end
end
