module Search
  module Builders
    # Items: one `item` document per live revision (staff: the prompt, the hints and the names of the typical errors), and one
    # document per instance. A practice item's instances are `practice_item` documents holding only what Items::Part serves
    # to the browser (passage, stem, options, rows); a diagnosis item's instances are `item_instance` documents for the
    # staff. Answers, solutions, error values and the answer key are in no document.
    module Items
      # D-402: a bilingual item holds each text in two layers, the target one (`_en`, `_es`) and its Italian; the index holds both, so the teacher finds
      # an item by the Italian words and by the words of the language it teaches (the document's `lang` stems both).
      LAYERS = %w[it en es].freeze
      PROMPT_KEYS = %w[stem passage answer_format steps].flat_map { |base| LAYERS.map { |l| "#{base}_#{l}" } }.freeze

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
        first = body["prompt"] || Array(body["sub_items"]).first&.dig("prompt") || {}
        stem = headline(::Items::Text.passage(body).presence || ::Items::Text.passage(first).presence || ::Items::Text.stem(first))
        item_doc = Doc.build(kind: "item", title: stem.presence || item.key, body: Text.join(item_text(body), body["component"], skill_of(body)), **context)
        [ item_doc ] + revision.instances.order(:id).map { |instance| instance_doc(item, revision, body, instance, context) }
      end

      def instance_doc(item, revision, body, instance, context)
        text = instance_text(body, JSON.parse(instance.display_json), item.subject)
        title = headline(instance_head(body, JSON.parse(instance.display_json), item.subject)).presence || Text.plain(text.first)
        if item.practice?
          Doc.build(kind: "practice_item", title: title, body: Text.join(text), anchor: instance.seed, unique: instance.id, **context)
        else
          Doc.build(kind: "item_instance", title: title, body: Text.join(text), anchor: instance.seed, unique: instance.id, **context)
        end
      end

      # The title of a hit is what tells one question from another: the case text, else the stem (not the generic prompt that
      # every question of a kind shares), first sentence only.
      def headline(text)
        Text.plain(text).split(/(?<=[.?!:])\s+/).first.to_s.first(140)
      end

      def instance_head(body, display, subject)
        part = ::Items::Part.new(subject: subject, after_answer: true)
        sub = body["kind"] == "testlet" ? nil : part.call(body, body["component"], display).stringify_keys
        (body["kind"] == "testlet" ? ::Items::Text.passage(body) : ::Items::Text.passage(sub).presence || ::Items::Text.stem(sub))
      end

      # The texts of +base+ in every layer +hash+ holds (a list is flattened).
      def layers(hash, base) = LAYERS.flat_map { |l| Array(hash["#{base}_#{l}"]) }

      def skill_of(body) = body["skill"] || Array(body["sub_items"]).first&.dig("skill")

      # What the browser is told of one shown instance (Items::Part), as plain words.
      def instance_text(body, display, subject)
        part = ::Items::Part.new(subject: subject, after_answer: true)
        parts = if body["kind"] == "testlet"
          sub_displays = Array(display["sub_items"]).to_h { |s| [ s["id"], s["display"] || {} ] }
          [ ::Items::Text.passage_keys(body) ] + Array(body["sub_items"]).map { |sub| part.call(sub, sub["component"], sub_displays.fetch(sub["id"], {})).stringify_keys }
        else
          [ part.call(body, body["component"], display).stringify_keys ]
        end
        parts.flat_map { |p| Text.strings(p.except("component", "figure", "lang")) + figure_alt(p) }.reject(&:blank?)
      end

      # The alt text of a figure in each layer it has.
      def figure_alt(part)
        figure = part["figure"].is_a?(Hash) ? part["figure"].transform_keys(&:to_s) : {}
        figure.slice(*LAYERS.map { |l| "alt_#{l}" }).values.map { |alt| Text.plain(alt) }
      end

      # The staff's text of an item revision: prompts, hints and the names of its typical errors (never an answer).
      def item_text(body)
        prompts = [ body["prompt"], *Array(body["sub_items"]).map { |s| s["prompt"] } ].compact.flat_map { |p| p.slice(*PROMPT_KEYS).values }
        errors = Array(body["error_catalogue"]).flat_map { |e| layers(e, "message") }
        [ *layers(body, "passage"), *prompts, *layers(body, "answer_format"), *layers(body, "hints"), *errors ].map { |t| Text.plain(t) }
      end
    end
  end
end
