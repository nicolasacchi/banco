# frozen_string_literal: true

module Lessons
  module Diagrams
    # mirror (WAVE2 2.6, T3): the Italian sentence over the target language, piece by piece, with links between the pieces (same, shift,
    # false_friend). A piece written 'Glie+lo' is one word written joined. The target language is read from the keys (pieces_en or pieces_es, one
    # for the whole figure, E-LESSON-LANG). The browser twin is lesson/diagrams/words/mirror.js; both run test/fixtures/diagrams/types/mirror.json.
    module Mirror
      extend Contract

      TARGET_KEYS = { "pieces_en" => "en", "pieces_es" => "es" }.freeze
      TEACHES = { "en" => "english", "es" => "spanish" }.freeze
      NEUTRAL_ALT = "Una frase in italiano e la stessa frase in un'altra lingua, divise in pezzi: tocca il pezzo che la domanda chiede."

      class << self
        def caps = Validation::Rules.get(:lesson2, :types, :mirror)

        # The words of config/locales/lesson_words.it.yml (key `scene`), the twin of lesson/diagrams/words/texts.js.
        def text(key) = I18n.t("lesson_words.scene.#{key}")

        def kind_word(kind) = text("link_#{kind}")

        def side_word(side) = text({ "it" => "italian_side", "en" => "english_side", "es" => "spanish_side" }.fetch(side))

        def show(piece) = piece.delete("+")

        def words_in(pieces) = pieces.sum { |p| show(p).split.size }

        def target_key(row) = TARGET_KEYS.keys.find { |k| row[k] }

        def lang_of(data) = TARGET_KEYS[data["rows"].filter_map { |r| target_key(r) }.first]

        # ---- checks -------------------------------------------------------------------------------------------------------------------

        def static(data, c)
          rows = data["rows"]
          keys = rows.map { |r| target_key(r) }
          rows.each_with_index do |row, i|
            at = "/rows/#{i}"
            both = TARGET_KEYS.keys.select { |k| row[k] }
            c.diagram(at, "a row has the Italian pieces and the pieces of one language: pieces_en or pieces_es (here #{both.size})", rule: "target#{at}") if both.size != 1
          end
          return if keys.any?(&:nil?) || rows.any? { |r| TARGET_KEYS.keys.count { |k| r[k] } != 1 }

          if keys.uniq.size > 1
            c.add("E-LESSON-LANG", "/rows", "a figure holds one language: #{keys.uniq.join(', ')}", rule: "one-language")
            return
          end
          lang = TARGET_KEYS.fetch(keys.first)
          c.add("E-LESSON-LANG", "/rows/0/#{keys.first}", "#{keys.first} is not a language this subject teaches", rule: "lang") unless TEACHES[lang] == c.subject
          rows.each_with_index { |row, i| row_checks(row, i, keys.first, lang, c) }
          if lang == "es"
            rows.each_with_index do |row, i|
              row["pieces_es"].each_with_index do |p, k|
                Words.tilde_warnings(show(p)).each { |w| c.add("W-ES-TILDE", "/rows/#{i}/pieces_es/#{k}", "the tilde of #{w} is not needed by the stress rule (or sits on the wrong syllable)", rule: "tilde-#{i}-#{k}-#{w}") }
              end
            end
          end
          links = rows.flat_map { |r| r["links"].to_a }
          if data["same_ok"]
            c.diagram("/same_ok", "same_ok is for a figure whose links are all the same", rule: "same-ok") if links.any? { |l| l[2] != "same" }
          elsif links.any? && links.all? { |l| l[2] == "same" }
            c.diagram("/rows", "every link is the same: a mirror shows what changes (same_ok: true says that sameness is the point)", rule: "all-same")
          end
        end

        def row_checks(row, i, key, lang, c)
          at = "/rows/#{i}"
          it = row["pieces_it"]
          tg = row[key]
          { "it" => it, lang => tg }.each do |side, pieces|
            n = words_in(pieces)
            c.diagram("#{at}/#{side == 'it' ? 'pieces_it' : key}", "a side has #{n} words (at most #{caps['words_per_side']})", rule: "side-words#{at}#{side}") if n > caps["words_per_side"]
          end
          sizes = { "it" => it.size, lang => tg.size }
          links = row["links"].to_a
          seen = []
          links.each_with_index do |l, k|
            lat = "#{at}/links/#{k}"
            if l[0] >= it.size || l[1] >= tg.size
              c.map(lat, "the link names a piece that does not exist", rule: "link-range#{lat}")
            elsif seen.include?(l[0, 2])
              c.map(lat, "the same link is written twice", rule: "link-twice#{lat}")
            end
            seen << l[0, 2]
          end
          return if links.any? { |l| l[0] >= it.size || l[1] >= tg.size }

          notes = row["notes"].to_a
          noted = []
          notes.each_with_index do |n, k|
            nat = "#{at}/notes/#{k}"
            if !sizes.key?(n["side"])
              c.diagram("#{nat}/side", "a note is on the Italian side or on the side of #{lang}", rule: "note-side#{nat}")
            elsif n["piece"] >= sizes[n["side"]]
              c.map("#{nat}/piece", "the note names a piece that does not exist", rule: "note-range#{nat}")
            elsif noted.include?([ n["side"], n["piece"] ])
              c.diagram(nat, "a piece has one note", rule: "note-twice#{nat}")
            end
            noted << [ n["side"], n["piece"] ]
            words = n["note_it"].split.size
            c.diagram("#{nat}/note_it", "a note has #{words} words (at most 12)", rule: "note-words#{nat}") if words > 12
          end
          links.each_with_index do |(a, b, kind), k|
            next if kind == "same"

            c.diagram("#{at}/notes", "the link #{k + 1} (#{kind_word(kind)}) needs a note on one of its pieces (note_it)", rule: "note-missing#{at}-#{k}") unless noted.include?([ "it", a ]) || noted.include?([ lang, b ])
          end
          it.each_index do |p|
            next if links.any? { |l| l[0] == p }

            c.diagram("#{at}/notes", "the Italian piece #{p + 1} has no link: it needs a note that says why", rule: "unlinked-it#{at}-#{p}") unless noted.include?([ "it", p ])
          end
          tg.each_index do |p|
            next if links.any? { |l| l[1] == p }

            c.diagram("#{at}/notes", "the piece #{p + 1} of #{lang} has no link: it needs a note that says why", rule: "unlinked-tg#{at}-#{p}") unless noted.include?([ lang, p ])
          end
          row["roles"].to_a.each_with_index do |r, k|
            rat = "#{at}/roles/#{k}"
            c.role("#{rat}/role", r["role"])
            if !sizes.key?(r["side"])
              c.diagram("#{rat}/side", "a role is on the Italian side or on the side of #{lang}", rule: "role-side#{rat}")
            elsif r["piece"] >= sizes[r["side"]]
              c.map("#{rat}/piece", "the role names a piece that does not exist", rule: "role-range#{rat}")
            end
          end
        end

        # ---- what the browser is told ------------------------------------------------------------------------------------------------

        def served(data, mode: :student)
          return StudentBody.diagram_generic(data) unless mode == :select

          rows = data["rows"].map do |r|
            key = target_key(r)
            { "pieces_it" => r["pieces_it"].map { |p| show(p) } }.merge(key ? { key => r[key].map { |p| show(p) } } : {})
          end
          { "type" => "mirror", "alt_it" => NEUTRAL_ALT, "rows" => rows }
        end

        # The stored ids of the pieces in reading order: r1i2 is the second Italian piece of the first row, r1t3 the third piece of the target side.
        def targets(data, set)
          raise ArgumentError, "mirror has no select set #{set.inspect}" unless set.to_s == "pieces"

          data["rows"].each_with_index.flat_map do |r, i|
            key = target_key(r)
            r["pieces_it"].each_index.map { |k| "r#{i + 1}i#{k + 1}" } + (key ? r[key].each_index.map { |k| "r#{i + 1}t#{k + 1}" } : [])
          end
        end

        # What a teacher reads for a stored id: the piece itself.
        def target_names(data, _set)
          data["rows"].each_with_index.flat_map do |r, i|
            key = target_key(r)
            r["pieces_it"].each_with_index.map { |t, k| [ "r#{i + 1}i#{k + 1}", show(t) ] } +
              (key ? r[key].each_with_index.map { |t, k| [ "r#{i + 1}t#{k + 1}", show(t) ] } : [])
          end.to_h
        end

        # ---- what the figure says and prints -----------------------------------------------------------------------------------------

        def describe(data, state: 0)
          rows = data["rows"]
          rows.each_with_index.map { |row, i| describe_row(row, i, rows.size > 1) }.join(" ")
        end

        def sentence(pieces) = pieces.map { |p| show(p) }.join(" ")

        def describe_row(row, i, several)
          key = target_key(row)
          return "" unless key

          lang = TARGET_KEYS[key]
          tg = row[key]
          it = row["pieces_it"]
          out = []
          out << "Coppia #{i + 1}." if several
          out << "Italiano: #{sentence(it)}."
          out << "#{side_word(lang)}: #{sentence(tg)}."
          row["links"].to_a.each { |a, b, kind| out << "#{show(it[a])} e #{show(tg[b])}: #{kind_word(kind)}." }
          row["notes"].to_a.each do |n|
            piece = n["side"] == "it" ? it[n["piece"]] : tg[n["piece"]]
            out << "Nota su #{show(piece)}: #{n['note_it']}."
          end
          it.each_index { |p| out << "#{show(it[p])}: #{text('link_none')}." unless row["links"].to_a.any? { |l| l[0] == p } }
          tg.each_index { |p| out << "#{show(tg[p])}: #{text('link_none')}." unless row["links"].to_a.any? { |l| l[1] == p } }
          out.join(" ")
        end

        def printed(data, _state)
          out = []
          data["rows"].each do |row|
            key = target_key(row)
            lang = TARGET_KEYS[key]
            it = row["pieces_it"]
            tg = key ? row[key] : []
            out.concat(it.map { |p| show(p) })
            out.concat(tg.map { |p| show(p) })
            out << sentence(it)
            out << sentence(tg) if key
            out.concat([ side_word("it"), side_word(lang) ].compact)
            out.concat(row["notes"].to_a.map { |n| n["note_it"] })
            out.concat(row["links"].to_a.map { |l| kind_word(l[2]) }.uniq)
            links = row["links"].to_a
            out << text("link_none") if it.each_index.any? { |p| links.none? { |l| l[0] == p } } || tg.each_index.any? { |p| links.none? { |l| l[1] == p } }
          end
          out << describe(data)
          out.compact.map(&:to_s).reject(&:empty?).uniq
        end
      end
    end
  end
end
