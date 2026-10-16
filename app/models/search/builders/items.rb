module Search
  module Builders
    # Items: one `item` document per live revision (staff: the prompt, the hints and the names of the typical errors), and one
    # document per instance. A practice item's instances are `practice_item` documents holding only what Items::Part serves
    # to the browser (passage, stem, options, rows); a diagnosis item's instances are `item_instance` documents for the
    # staff. Answers, solutions, error values and the answer key are in no document.
    module Items
      PROMPT_KEYS = %w[stem_it passage_it answer_format_it steps_it].freeze

      module_function

      def call
        Live.item_revisions.flat_map { |revision| docs_of(revision) }
      end

      def docs_of(revision)
        item = revision.item
        body = JSON.parse(revision.body_json)
        subject = item.subject
        lang = ::Lessons::Lang.target(subject.key) || "it"
        context = { key: item.key, subject: subject.key, revision_table: "item_revisions", revision_id: revision.id, status: revision.status,
                    skill: skill_of(body), lang: lang }
        stem = Text.plain(body.dig("prompt", "stem_it") || Array(body["sub_items"]).first&.dig("prompt", "stem_it"))
        item_doc = Doc.build(kind: "item", title: stem.presence || item.key, body: Text.join(item_text(body), body["component"], skill_of(body)), **context)
        [ item_doc ] + revision.instances.order(:id).map { |instance| instance_doc(item, revision, body, instance, context) }
      end

      def instance_doc(item, revision, body, instance, context)
        text = instance_text(body, JSON.parse(instance.display_json), item.subject)
        title = Text.plain(text.first)
        if item.practice?
          Doc.build(kind: "practice_item", title: title, body: Text.join(text), anchor: instance.seed, unique: instance.id, **context)
        else
          Doc.build(kind: "item_instance", title: title, body: Text.join(text), anchor: instance.seed, unique: instance.id, **context)
        end
      end

      def skill_of(body) = body["skill"] || Array(body["sub_items"]).first&.dig("skill")

      # What the browser is told of one shown instance (Items::Part), as plain words.
      def instance_text(body, display, subject)
        part = ::Items::Part.new(subject: subject)
        parts = if body["kind"] == "testlet"
          sub_displays = Array(display["sub_items"]).to_h { |s| [ s["id"], s["display"] || {} ] }
          [ { "passage_it" => body["passage_it"] } ] + Array(body["sub_items"]).map { |sub| part.call(sub, sub["component"], sub_displays.fetch(sub["id"], {})).stringify_keys }
        else
          [ part.call(body, body["component"], display).stringify_keys ]
        end
        parts.flat_map { |p| Text.strings(p.except("component", "figure")) + figure_alt(p) }.reject(&:blank?)
      end

      def figure_alt(part) = [ Text.plain(part.dig("figure", :alt_it) || part.dig("figure", "alt_it")) ]

      # The staff's text of an item revision: prompts, hints and the names of its typical errors (never an answer).
      def item_text(body)
        prompts = [ body["prompt"], *Array(body["sub_items"]).map { |s| s["prompt"] } ].compact.flat_map { |p| p.slice(*PROMPT_KEYS).values }
        errors = Array(body["error_catalogue"]).map { |e| e["message_it"] }
        [ body["passage_it"], *prompts, *body["answer_format_it"], *Array(body["hints_it"]), *errors ].map { |t| Text.plain(t) }
      end
    end
  end
end
