# frozen_string_literal: true

require "digest"

module Practice
  # Serving (A8.7). choose is the pure rule; next reads the student's rows, applies it and appends the
  # serve in ONE transaction (SQLite BEGIN IMMEDIATE, the Rails default), so two tabs, an outbox retry
  # or a reload get the same open serve and no instance is burnt twice (A8.4).
  #
  #   Practice::Selector.next(student:, topic_revision:, skill:, follow: nil, now:)
  #     # => Choice(instance, reason, parent_serve_id, error_code, serve, created)
  #
  # follow: {serve_id:, kind: "prova_questo" | "after_solution"}. Raises BadFollow (HTTP 422
  # bad_follow) and NotPinned (HTTP 404) as the spec says.
  module Selector
    V1 = Rules::V1

    Candidate = Data.define(:instance_id, :item_id, :item_revision_id, :fingerprint, :error_codes)
    Pick = Data.define(:candidate, :reason, :error_code, :parent_serve_id)
    Choice = Data.define(:instance, :reason, :parent_serve_id, :error_code, :serve, :created)
    Follow = Data.define(:serve_id, :kind, :item_id, :item_revision_id, :error_code)

    class BadFollow < StandardError; end
    class NotPinned < StandardError; end

    module_function

    # ---- the pure rule ------------------------------------------------------------------------------

    # pool: [Candidate] in pin order, then instance id. seen: Set of fingerprints served before.
    # last_serve: {fingerprint => id of the latest serve}; item_last_serve: {item_id => same};
    # credit_by_item: {item_id => C_unaided tries}; follow: Follow or nil. Returns a Pick, or nil when the
    # pool is empty.
    def choose(pool:, student_id:, seen:, last_serve:, item_last_serve:, credit_by_item:, follow: nil)
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
      pick = next_unseen(pool, unseen, item_last_serve, credit_by_item)
      return Pick.new(pick, "next", nil, parent) if pick

      oldest = pool.min_by { |c| [ last_serve.fetch(c.fingerprint, 0), order_key(student_id, c) ] }
      Pick.new(oldest, "reseen", nil, parent)
    end

    # Rule 4: the current item (pin order, fewer than ADVANCE_AFTER_CORRECT_UNAIDED credits; else the item
    # served least recently), then the following pinned items with an unseen instance.
    def next_unseen(pool, unseen, item_last_serve, credit_by_item)
      items = pool.map(&:item_id).uniq
      current = items.find { |i| credit_by_item.fetch(i, 0) < V1::ADVANCE_AFTER_CORRECT_UNAIDED } ||
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

    def next(student:, topic_revision:, skill:, follow: nil, now: Time.current)
      practice = topic_revision.body["practice"].find { |p| p["skill"] == skill } or raise NotPinned, skill
      subject = Subject.find_by!(key: skill.split(".").first)
      PracticeServe.transaction do
        input = Loader.for(student, subject: subject, skill: skill, seeds: false, now: now)
        followed = validate_follow(input, follow)
        open = input.serves.reverse.find { |s| s.status.state == :open }
        if open
          serve = PracticeServe.find(open.id)
          Choice.new(serve.item_instance, serve.reason, serve.parent_serve_id, serve.error_code, serve, false)
        else
          create_serve(student, topic_revision, skill, practice, input, followed, now)
        end
      end
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

    def create_serve(student, topic_revision, skill, practice, input, followed, now)
      pool = pool_for(practice)
      pick = choose(pool: pool, student_id: student.id, follow: followed,
                    seen: input.serves.map(&:fingerprint).to_set,
                    last_serve: last_by(input.serves, :fingerprint), item_last_serve: last_by(input.serves, :item_id),
                    credit_by_item: input.tries.select { |t| t.evidence == :C && !t.aided && !t.reseen }.group_by(&:item_id).transform_values(&:size)) or
        raise NotPinned, skill
      instance = ItemInstance.includes(:item_revision).find(pick.candidate.instance_id)
      seed = Digest::SHA256.hexdigest("#{student.id}:#{instance.id}:#{input.serves.size}")[0, 8].to_i(16)
      rekeyed = Diagnosis::Conductor.rekey(instance, JSON.parse(instance.item_revision.body_json), "#{seed}|#{instance.id}")
      serve = PracticeServe.create!(student: student, topic_revision: topic_revision, item_instance: instance, skill_key: skill, reason: pick.reason,
                                    parent_serve_id: pick.parent_serve_id, error_code: pick.error_code, seed: seed,
                                    shown_order_json: rekeyed.shown_order.to_json, id_map_json: rekeyed.id_map.to_json,
                                    rules_version: V1::RULES_VERSION, created_at: now)
      Choice.new(instance, pick.reason, pick.parent_serve_id, pick.error_code, serve, true)
    end

    def last_by(serves, field)
      serves.each_with_object({}) { |s, h| key = s.public_send(field); h[key] = [ h[key], s.id ].compact.max }
    end

    # Candidates of the pinned item revisions of a skill, in pin order then instance id.
    def pool_for(practice)
      practice["items"].flat_map do |pin|
        revision = ItemRevision.find(pin["revision"])
        revision.instances.order(:id).map do |i|
          codes = i.errors_json.present? ? JSON.parse(i.errors_json).map { |e| e["code"] } : []
          Candidate.new(instance_id: i.id, item_id: revision.item_id, item_revision_id: revision.id, fingerprint: i.fingerprint, error_codes: codes)
        end
      end
    end
  end
end
