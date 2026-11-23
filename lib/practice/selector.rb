# frozen_string_literal: true

require "digest"

module Practice
  # Serving (A8.7). choose is the pure rule; next reads the student's rows, applies it and appends the
  # serve in ONE transaction (SQLite BEGIN IMMEDIATE, the Rails default) that re-reads the open serves, so
  # two tabs, an outbox retry or a reload get the same open serve and no instance is burnt twice (A8.4).
  # There is at most one open serve per student, skill and pinned item (practice/6, docs/rules/practice-6.md).
  #
  #   Practice::Selector.next(student:, topic_revision:, skill:, follow: nil, item: nil, advance: false, shown: nil, now:)
  #     # => Choice(instance, reason, parent_serve_id, error_code, serve, created), or EXHAUSTED
  #
  # EXHAUSTED: the skill has no instance this student has not seen and no open serve to resume. Nothing is served on its own (D-348); the
  # fact is recorded once (PracticePoolExhaustion) and the page says so. Choosing an item (item:) still redoes it, reason reseen.
  #
  # item: an item KEY: that item's open serve, else a new instance of it. follow: {serve_id:, kind:
  # "prova_questo" | "after_solution"}. advance: the next exercise that is not open («Avanti», «Salta»).
  # None of them: the open serve touched most recently (the first load of the page), else the next exercise.
  # shown: {lesson id => TopicRevision} the student is shown (Course::StudentView#shown_revisions); nil: only `topic_revision`. A serve made on
  # another revision of a shown lesson is replaced (D-377): never resumed, and its instance is not counted as seen. When the latest serve touched
  # is a replaced one, the next serve is of its item if the revision still pins it.
  # Raises BadFollow (HTTP 422 bad_follow) and NotPinned (HTTP 404) as the spec says.
  module Selector
    V6 = Rules::V6

    Candidate = Data.define(:instance_id, :item_id, :item_revision_id, :fingerprint, :error_codes)
    Pick = Data.define(:candidate, :reason, :error_code, :parent_serve_id)
    Choice = Data.define(:instance, :reason, :parent_serve_id, :error_code, :serve, :created)
    Follow = Data.define(:serve_id, :kind, :item_id, :item_revision_id, :error_code)

    # What `next` answers when there is nothing to serve because every instance was seen (practice/6 section 7, rule 8).
    EXHAUSTED = :exhausted

    class BadFollow < StandardError; end
    class NotPinned < StandardError; end

    module_function

    # ---- the pure rule ------------------------------------------------------------------------------

    # pool: [Candidate] in pin order, then instance id. seen: Set of fingerprints served before.
    # last_serve: {fingerprint => id of the latest serve}; item_last_serve: {item_id => same};
    # credit_by_item: {item_id => C_unaided tries}; follow: Follow or nil; open_item_ids: Set of the item ids
    # that have an open serve (their candidates are left out); pick_item_id: serve this item and no other
    # (the open serve check is the caller's). hard: the Set of the fingerprints of the hard-to-guess instances when the skill still needs them
    # and nothing else (hard_needed?, D-390): the automatic choice then takes an unseen one of those when the pool has any. Returns a Pick, or nil when no candidate is left. Without pick_item_id no seen instance is ever
    # picked (D-348): nil also when every candidate was seen; exhausted? tells that case from the items having an open serve.
    def choose(pool:, student_id:, seen:, last_serve:, item_last_serve:, credit_by_item:, follow: nil, open_item_ids: Set.new, pick_item_id: nil, hard: nil)
      pool = pool.select { |c| c.item_id == pick_item_id } if pick_item_id
      pool = pool.reject { |c| open_item_ids.include?(c.item_id) } unless pick_item_id
      return nil if pool.empty?

      unseen = pool.reject { |c| seen.include?(c.fingerprint) }.sort_by { |c| order_key(student_id, c) }
      parent = follow&.serve_id
      if follow&.kind == "prova_questo"
        code = follow.error_code
        hit = unseen.select { |c| c.error_codes.include?(code) }
        pick = hit.find { |c| c.item_revision_id == follow.item_revision_id } || hit.first
        return Pick.new(pick, "prova_questo", code, parent) if pick
      elsif follow&.kind == "after_solution"
        pick = unseen.find { |c| c.item_revision_id == follow.item_revision_id }
        return Pick.new(pick, "after_solution", nil, parent) if pick
      end
      pick = next_unseen(pool, prefer_hard(unseen, hard), item_last_serve, credit_by_item)
      return Pick.new(pick, "next", nil, parent) if pick
      return nil unless pick_item_id

      oldest = pool.min_by { |c| [ last_serve.fetch(c.fingerprint, 0), order_key(student_id, c) ] }
      Pick.new(oldest, "reseen", nil, parent)
    end

    # true when every candidate of the skill was served to this student: no unseen instance is left (the open serves do not matter).
    def exhausted?(pool:, seen:) = !pool.empty? && pool.all? { |c| seen.include?(c.fingerprint) }

    # D-390: the unseen instances that are hard to guess when the skill needs those and some exist; else all of them.
    def prefer_hard(unseen, hard)
      return unseen unless hard

      hard_ones = unseen.select { |c| hard.include?(c.fingerprint) }
      hard_ones.empty? ? unseen : hard_ones
    end

    # D-390: true when the tries that count (right, without help, one per fingerprint) leave DEMONSTRATE_MIN_LOW_GUESS short and no fewer exercises
    # are missing in all than hard ones: every exercise still to come must be hard to guess (a written answer, a matching, an ordering). `tries`: the
    # skill's Practice::Try rows.
    def hard_needed?(tries)
      credits = tries.select { |t| t.evidence == :C && !t.aided && !t.reseen }.uniq(&:fingerprint)
      need = [ V6::DEMONSTRATE_CORRECT_UNAIDED - credits.size, 0 ].max
      need_hard = [ V6::DEMONSTRATE_MIN_LOW_GUESS - credits.count(&:low_guess), 0 ].max
      need_hard.positive? && need_hard >= need
    end

    # Rule 4: the current item (pin order, fewer than ADVANCE_AFTER_CORRECT_UNAIDED credits; else the item
    # served least recently), then the following pinned items with an unseen instance.
    def next_unseen(pool, unseen, item_last_serve, credit_by_item)
      items = pool.map(&:item_id).uniq
      current = items.find { |i| credit_by_item.fetch(i, 0) < V6::ADVANCE_AFTER_CORRECT_UNAIDED } ||
                items.min_by.with_index { |i, pos| [ item_last_serve.fetch(i, 0), pos ] }
      rotated = items.rotate(items.index(current))
      rotated.each do |item|
        pick = unseen.find { |c| c.item_id == item }
        return pick if pick
      end
      nil
    end

    def order_key(student_id, candidate) = Digest::SHA256.hexdigest("#{student_id}:#{candidate.fingerprint}")

    # ---- the serve, in one transaction ---------------------------------------------------------------

    def next(student:, topic_revision:, skill:, follow: nil, item: nil, advance: false, shown: nil, now: Time.current)
      practice = topic_revision.body["practice"].find { |p| p["skill"] == skill } or raise NotPinned, skill
      subject = Subject.find_by!(key: skill.split(".").first)
      revisions = practice["items"].map { |pin| ItemRevision.find(pin["revision"]) }
      item_id = pinned_item_id(item, revisions, skill)
      PracticeServe.transaction do
        input = Loader.for(student, subject: subject, skill: skill, seeds: false, now: now, shown: shown || { topic_revision.lesson_id => topic_revision })
        followed = validate_follow(input, follow)
        pinned = revisions.map(&:item_id).to_set
        open = open_serves(input, pinned)
        replaced = replaced_serves(input, pinned)
        touched = touched_at(student, input, open + replaced)
        by_item = open.group_by(&:item_id).transform_values { |rows| rows.max_by(&:id) }
        if item_id
          resume(by_item[item_id]) || create_serve(student, topic_revision, skill, revisions, input, nil, now, pick_item_id: item_id) || raise(NotPinned, skill)
        elsif followed || advance
          # a follow already answered (two tabs, a retry) gives its serve again while that serve is open
          child = followed && open.select { |s| s.parent_serve_id == followed.serve_id }.max_by(&:id)
          resume(child) || serve_or_resume(student, topic_revision, skill, revisions, input, followed, now, by_item.keys.to_set,
                                           by_item[followed&.item_id] || open.min_by { |s| [ touched[s.id], s.id ] })
        else
          latest = (open + replaced).max_by { |s| [ touched[s.id], s.id ] }
          # the exercise he was on was replaced by a new version of the topic: the same item again, from the revision he is shown now
          made = latest && latest.status.state == :replaced && !by_item.key?(latest.item_id) &&
                 create_serve(student, topic_revision, skill, revisions, input, nil, now, pick_item_id: latest.item_id)
          made || resume(open.max_by { |s| [ touched[s.id], s.id ] }) || serve_or_resume(student, topic_revision, skill, revisions, input, nil, now, Set.new, nil)
        end
      end
    end

    # The id of the item with that key when it is pinned on the skill; nil without a key; else NotPinned.
    def pinned_item_id(key, revisions, skill)
      return nil unless key

      id = Item.find_by(key: key.to_s)&.id
      raise NotPinned, skill unless id && revisions.any? { |r| r.item_id == id }

      id
    end

    # The open serves of the skill on pinned items, as ServeRows.
    def open_serves(input, pinned_item_ids)
      input.serves.select { |s| s.status.state == :open && pinned_item_ids.include?(s.item_id) }
    end

    # The replaced serves of the skill on pinned items (D-377), as ServeRows: no longer offered, they only tell which exercise he was on.
    def replaced_serves(input, pinned_item_ids)
      input.serves.select { |s| s.status.state == :replaced && pinned_item_ids.include?(s.item_id) }
    end

    # {serve id => the latest of its creation, its last try and its last draft}.
    def touched_at(student, input, open)
      drafts = defined?(PracticeDraft) ? PracticeDraft.where(student_id: student.id, practice_serve_id: open.map(&:id)).group(:practice_serve_id).maximum(:created_at) : {}
      last_try = input.tries.group_by(&:serve_id).transform_values { |tries| tries.map(&:at).max }
      open.to_h { |s| [ s.id, [ s.at, last_try[s.id], drafts[s.id] ].compact.max ] }
    end

    # The Choice of an open serve as it is, or nil without one.
    def resume(row)
      return nil unless row

      serve = PracticeServe.find(row.id)
      Choice.new(serve.item_instance, serve.reason, serve.parent_serve_id, serve.error_code, serve, false)
    end

    # A follow must name a serve of this student and skill that allows it (its actions say so): an open
    # serve, another student's, or one that does not allow it is bad.
    def validate_follow(input, follow)
      return nil unless follow

      follow = follow.to_h.symbolize_keys

      kind = follow[:kind].to_s
      raise BadFollow, "kind" unless %w[prova_questo after_solution].include?(kind)

      row = input.serves.find { |s| s.id == follow[:serve_id].to_i } or raise BadFollow, "serve"
      raise BadFollow, "not allowed" unless row.status.actions.include?(kind.to_sym)

      code = nil
      if kind == "prova_questo"
        code = input.tries.select { |t| t.serve_id == row.id && t.outcome == :typical_error }.last&.error_codes&.first
        raise BadFollow, "no typical error" unless code
      end
      Follow.new(serve_id: row.id, kind: kind, item_id: row.item_id, item_revision_id: row.item_revision_id, error_code: code)
    end

    # A new serve when there is an unseen instance to give; else the open serve to resume (`fallback`, may be nil); else EXHAUSTED when no
    # instance is unseen (recorded once); else NotPinned (every pinned item open and no serve to resume, or an item without instances).
    def serve_or_resume(student, topic_revision, skill, revisions, input, followed, now, open_item_ids, fallback)
      made = create_serve(student, topic_revision, skill, revisions, input, followed, now, open_item_ids: open_item_ids)
      return made if made.is_a?(Choice)

      resume(fallback) || (made == EXHAUSTED ? EXHAUSTED : raise(NotPinned, skill))
    end

    # The new serve; nil when choose has no candidate (every pinned item open, or the item has no instance); EXHAUSTED (and the row recorded)
    # when the choice was not the student's own (no pick_item_id) and every instance of the skill was seen.
    def create_serve(student, topic_revision, skill, revisions, input, followed, now, open_item_ids: Set.new, pick_item_id: nil)
      pool = pool_for(revisions)
      # a replaced serve was never finished and its exercise is withdrawn: its instance is not seen (D-377)
      seen = input.serves.reject { |s| s.status.state == :replaced }.map(&:fingerprint).to_set
      hard = hard_fingerprints(revisions) if !pick_item_id && hard_needed?(input.tries)
      pick = choose(pool: pool, student_id: student.id, follow: followed, open_item_ids: open_item_ids, pick_item_id: pick_item_id, hard: hard,
                    seen: seen, last_serve: last_by(input.serves, :fingerprint), item_last_serve: last_by(input.serves, :item_id),
                    credit_by_item: input.tries.select { |t| t.evidence == :C && !t.aided && !t.reseen }.group_by(&:item_id).transform_values(&:size))
      unless pick
        return nil if pick_item_id || !exhausted?(pool: pool, seen: seen)

        PracticePoolExhaustion.record!(student: student, topic_revision: topic_revision, skill_key: skill, now: now)
        return EXHAUSTED
      end
      instance = ItemInstance.includes(:item_revision).find(pick.candidate.instance_id)
      seed = Digest::SHA256.hexdigest("#{student.id}:#{instance.id}:#{input.serves.size}")[0, 8].to_i(16)
      rekeyed = Diagnosis::Conductor.rekey(instance, JSON.parse(instance.item_revision.body_json), "#{seed}|#{instance.id}")
      serve = PracticeServe.create!(student: student, topic_revision: topic_revision, item_instance: instance, skill_key: skill, reason: pick.reason,
                                    parent_serve_id: pick.parent_serve_id, error_code: pick.error_code, seed: seed,
                                    shown_order_json: rekeyed.shown_order.to_json, id_map_json: rekeyed.id_map.to_json,
                                    rules_version: V6::RULES_VERSION, created_at: now)
      Choice.new(instance, pick.reason, pick.parent_serve_id, pick.error_code, serve, true)
    end

    # The fingerprints of the hard-to-guess instances of the pinned revisions (Practice::Instances.low_guess?, the fold's own test).
    def hard_fingerprints(revisions)
      revisions.flat_map { |revision| revision.instances.select { |i| Instances.low_guess?(i) }.map(&:fingerprint) }.to_set
    end

    def last_by(serves, field)
      serves.each_with_object({}) { |s, h| key = s.public_send(field); h[key] = [ h[key], s.id ].compact.max }
    end

    # Candidates of the pinned item revisions of a skill, in pin order then instance id.
    def pool_for(revisions)
      revisions.flat_map do |revision|
        revision.instances.order(:id).map do |i|
          codes = i.errors_json.present? ? JSON.parse(i.errors_json).map { |e| e["code"] } : []
          Candidate.new(instance_id: i.id, item_id: revision.item_id, item_revision_id: revision.id, fingerprint: i.fingerprint, error_codes: codes)
        end
      end
    end
  end
end
