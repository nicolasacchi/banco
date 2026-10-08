module Validation
  # The synchronous checks of a topic (banco.topic/1, A2.3, A3.2). A topic pins one lesson revision and, per
  # skill, 2 to 4 practice item revisions; "latest" resolves at submit (a lesson: its newest revision; an item:
  # its newest passed revision). Reads rows; nothing is written. Result: findings and the stored body (integers
  # only) when there is no error.
  module TopicChecks
    Result = Struct.new(:findings, :stored, :lesson_revision, :item_revisions, keyword_init: true)

    module_function

    def call(doc, subject:)
      findings = Findings.new
      return Result.new(findings: findings) unless SchemaCheck.call("topic", doc, findings)

      key = doc["key"]
      if doc["subject"] != subject.key || key.split(".", 3)[1] != subject.key
        findings.add("E-SCHEMA", "/subject", "the topic #{key} is for #{key.split('.', 3)[1]}, submitted for #{subject.key}", rule: "subject")
        return Result.new(findings: findings)
      end
      course = CourseRevision.where(subject: subject).order(:seq).last
      entry = course && JSON.parse(course.body_json)["topics"].find { |t| t["key"] == key }
      unless entry
        findings.add("E-TOPIC-UNKNOWN", "/key", course ? "#{key} is not a topic of the latest course map of #{subject.key}" : "#{subject.key} has no course map yet", rule: "unknown")
        return Result.new(findings: findings)
      end

      lesson, lesson_revision = lesson_pin(doc, key, entry, findings)
      practice_skills(doc, entry, findings)
      resolved = pins(doc, subject, findings)
      pool(resolved, findings)
      instances_vs_lesson(resolved, lesson_revision, findings) if lesson_revision
      overlap(resolved, subject, findings)
      return Result.new(findings: findings) if findings.any_error? || lesson.nil?

      stored = doc.merge("lesson_revision" => lesson_revision.id,
                         "practice" => resolved.map { |entry_pins| { "skill" => entry_pins[:skill], "items" => entry_pins[:pins].map { |p| { "item" => p[:key], "revision" => p[:revision].id } } } })
      Result.new(findings: findings, stored: stored, lesson_revision: lesson_revision, item_revisions: resolved.flat_map { |e| e[:pins].map { |p| p[:revision] } })
    end

    def lesson_pin(doc, key, entry, findings)
      lesson = Lesson.find_by(key: key)
      unless lesson&.latest_revision
        findings.add("E-TOPIC-PIN", "/lesson_revision", "there is no lesson #{key}: submit it first (banco lesson submit DIR)", rule: "no_lesson")
        return [ nil, nil ]
      end
      pin = doc["lesson_revision"]
      revision = pin == "latest" ? lesson.latest_revision : lesson.revisions.find { |r| r.id == pin }
      unless revision
        findings.add("E-TOPIC-PIN", "/lesson_revision", "revision #{pin} is not a revision of the lesson #{key}", rule: "lesson_pin")
        return [ lesson, nil ]
      end
      unless revision.body["skills"].sort == entry["skills"].sort
        findings.add("E-TOPIC-SKILLS", "/lesson_revision", "the lesson revision #{revision.id} teaches #{revision.body['skills'].join(', ')}; the course map has #{entry['skills'].join(', ')} for this topic", rule: "lesson_skills")
      end
      [ lesson, revision ]
    end

    # The practice entries cover exactly the skills of the topic in the map, each once.
    def practice_skills(doc, entry, findings)
      skills = doc["practice"].map { |p| p["skill"] }
      findings.add("E-TOPIC-SKILLS", "/practice", "a skill appears twice in practice", rule: "twice") if skills.uniq.size != skills.size
      return if skills.sort == entry["skills"].sort

      findings.add("E-TOPIC-SKILLS", "/practice", "practice has #{skills.sort.join(', ')}; the course map has #{entry['skills'].sort.join(', ')} for this topic", rule: "map")
    end

    # [{skill:, pins: [{key:, revision:, info:}]}] for what resolved; findings for what did not.
    def pins(doc, subject, findings)
      seen = {}
      doc["practice"].each_with_index.map do |entry, i|
        list = entry["items"].each_with_index.filter_map do |pin, j|
          field = "/practice/#{i}/items/#{j}"
          item = Item.find_by(subject: subject, key: pin["item"])
          unless item
            findings.add("E-TOPIC-PIN", field, "there is no item #{pin['item']} in #{subject.key}", rule: "no_item-#{pin['item']}")
            next
          end
          findings.add("E-TOPIC-SKILLS", field, "#{pin['item']} is pinned twice", rule: "item_twice-#{pin['item']}") if seen[item.id]
          seen[item.id] = true
          revision = resolve_item(item, pin["revision"], field, findings) or next
          info = ItemInfo.for(revision)
          unless item.practice?
            findings.add("E-TOPIC-ITEM-KIND", field, "#{pin['item']} is a #{item.kind}: a topic pins practice items only", rule: "kind-#{pin['item']}")
            next
          end
          unless info.skills.include?(entry["skill"])
            findings.add("E-TOPIC-ITEM-KIND", field, "#{pin['item']} measures #{info.skills.join(', ')}, not #{entry['skill']}", rule: "skill-#{pin['item']}")
            next
          end
          { key: pin["item"], revision: revision, info: info, level: JSON.parse(revision.body_json)["level"] }
        end
        { skill: entry["skill"], pins: list }
      end
    end

    def resolve_item(item, pin, field, findings)
      revisions = item.revisions.includes(:validations)
      newest_passed = revisions.select { |r| r.status == "passed" }.max_by(&:seq)
      if pin == "latest"
        findings.add("E-ITEM-NOT-PASSED", field, "#{item.key} has no passed revision yet", rule: "none_passed-#{item.key}") unless newest_passed
        return newest_passed
      end
      revision = revisions.find { |r| r.id == pin }
      unless revision
        findings.add("E-TOPIC-PIN", field, "revision #{pin} is not a revision of #{item.key}", rule: "item_pin-#{item.key}")
        return nil
      end
      if revision.status != "passed"
        findings.add("E-ITEM-NOT-PASSED", field, "item revision #{pin} has no passed validation", rule: "not_passed-#{pin}")
        return nil
      end
      if newest_passed && newest_passed.id != revision.id
        findings.add("W-STALE-PIN", field, "item revision #{pin} is no longer the latest passed revision of #{item.key}: #{newest_passed.id} replaced it; pin #{newest_passed.id}", rule: "stale_pin-#{pin}", revision: pin, latest: newest_passed.id)
      end
      revision
    end

    # Per skill: a level 1 item, enough distinct fingerprints, enough hard-to-guess ones.
    def pool(resolved, findings)
      min = Rules.get(:practice, :topic_min_instances_per_skill)
      low = Rules.get(:practice, :topic_min_low_guess_instances_per_skill)
      resolved.each_with_index do |entry, i|
        next if entry[:pins].empty?

        field = "/practice/#{i}/items"
        findings.add("E-TOPIC-POOL", field, "#{entry[:skill]} has no level 1 item: add an item with level 1", rule: "level1-#{entry[:skill]}") unless entry[:pins].any? { |p| p[:level] == 1 }
        instances = entry[:pins].flat_map { |p| p[:info].instances }.uniq { |x| x[:fingerprint] }
        if instances.size < min
          findings.add("E-TOPIC-POOL", field, "#{entry[:skill]} has #{instances.size} distinct instances (at least #{min})", rule: "size-#{entry[:skill]}", count: instances.size)
        elsif instances.count { |x| x[:low_guess] } < low
          findings.add("E-TOPIC-POOL", field, "#{entry[:skill]} has #{instances.count { |x| x[:low_guess] }} hard-to-guess instances (at least #{low})", rule: "low_guess-#{entry[:skill]}", count: instances.count { |x| x[:low_guess] })
        end
      end
    end

    # A pinned instance that repeats a worked example or an exercise of the lesson: the same text, or the same formulas.
    def instances_vs_lesson(resolved, lesson_revision, findings)
      lines = lesson_lines(lesson_revision.body)
      return if lines.empty?

      resolved.each do |entry|
        entry[:pins].each do |pin|
          pin[:revision].instances.each do |inst|
            stem = JSON.parse(inst.display_json)["stem_it"].to_s
            next if stem.empty?

            next unless lines.any? { |line| same_line?(stem, line) }

            findings.add("W-TOPIC-INSTANCE-IN-LESSON", "/practice", "an instance of #{pin[:key]} (seed #{inst.seed}) repeats a line of the lesson: S would see the worked answer", rule: "in_lesson-#{pin[:key]}", seed: inst.seed)
          end
        end
      end
    end

    def lesson_lines(body)
      from_blocks = Lessons::Markup.raw_blocks(body["sections"]["example_it"]).flat_map { |b| b.type == :p ? [ b.text ] : b.items.flat_map { |i| [ i[:text] ] + i[:subs] } }
      body["exercises"].map { |e| e["text_it"] } + from_blocks
    end

    def same_line?(stem, line)
      return true if flat(stem) == flat(line)

      mine = formulas(stem)
      mine.any? && mine == formulas(line)
    end

    def flat(text) = text.to_s.downcase.delete("$ ").tr("−", "-")
    def formulas(text) = text.to_s.scan(/\$([^$]+)\$/).flatten.map { |f| flat(f) }.sort

    # A pinned instance that has the fingerprint of a diagnosis instance of the same skill (S has met it).
    def overlap(resolved, subject, findings)
      resolved.each do |entry|
        prints = entry[:pins].flat_map { |p| p[:info].instances.map { |x| x[:fingerprint] } }.uniq
        next if prints.empty?

        hits = ItemInstance.joins(item_revision: :item).where(items: { subject_id: subject.id, kind: Item::DIAGNOSIS_KINDS }, fingerprint: prints).includes(:item_revision).select do |inst|
          body = JSON.parse(inst.item_revision.body_json)
          ([ body["skill"] ] + Array(body["sub_items"]).map { |s| s["skill"] }).include?(entry[:skill])
        end
        next if hits.empty?

        findings.add("W-PRACTICE-DIAGNOSIS-OVERLAP", "/practice", "#{hits.size} pinned instance(s) of #{entry[:skill]} are instances of the diagnosis too: S has seen them", rule: "overlap-#{entry[:skill]}", count: hits.size)
      end
    end
  end
end
