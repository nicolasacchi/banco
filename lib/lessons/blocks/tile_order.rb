# frozen_string_literal: true

module Lessons
  module Blocks
    # W-TILE-ORDER (D-402, round 8): a tiles check that builds a sentence of English or Spanish is graded by the order of its tiles, and a sentence that is right in
    # another order, with only its time or place phrase somewhere else («Por la mañana mi hermana se ducha» beside «Mi hermana se ducha por la mañana»), is refused
    # unless the author accepted it. The most frequent refused-answer major of the third wave was exactly that.
    #
    # A time or place phrase is a tile, or a run of tiles, that starts with a word of PHRASE (a time word or a preposition of time or place) and goes on over the
    # tiles of LINK (articles, prepositions, the words that only lead into the phrase) up to the first tile that is not one of them: «por la mañana», «En 1973»,
    # «hoy», «after school». Each such phrase is moved, alone, to the start, to the end and one or two tiles before and one after where it stands (next to a verb of one or two tiles); an order that is not
    # the key, not accepted and not a declared error value is listed. Only a warning: the author reads the orders and accepts the right ones.
    module TileOrder
      PHRASE = {
        "en" => %w[in on at under over near behind beside between inside outside across around during after before since until yesterday today tomorrow tonight now
                   then soon later here there every last next],
        "es" => %w[en sobre bajo ante entre detrás delante cerca lejos dentro fuera durante después antes desde hasta por hoy ayer mañana anoche ahora luego pronto
                   aquí allí ahí cada todos todas]
      }.freeze
      LINK = {
        "en" => %w[in on at under over near behind beside between inside outside across around during after before since until every last next the a an of my your his
                   her our their this that these those one two],
        "es" => %w[en sobre bajo ante entre detrás delante cerca lejos dentro fuera durante después antes desde hasta por cada todos todas de del a al el la los las un
                   una unos unas mi tu su mis tus sus]
      }.freeze
      SHOWN = 4

      module_function

      # Adds the warning to +ctx+ for the tiles +check+ when there is an order to list.
      def check(check, ctx)
        orders = orders(check)
        return if orders.empty?

        ctx.add("W-TILE-ORDER", "answer", message(orders), rule: "tile-order", orders: orders)
      end

      # The orders to list for +check+ ({"tiles" => [{"id", "text_en"|"text_es"}], "answer" => ids, "accept" => [ids], "errors" => [{"answer" => ids}]}): lower-case
      # sentences, [] when the tiles are not English or Spanish words or the answer is shorter than three tiles.
      def orders(check)
        tiles = check["tiles"].to_a.to_h { |t| [ t["id"], t ] }
        lang = language(tiles.values)
        answer = Array(check["answer"])
        return [] unless lang && answer.size >= 3 && answer.all? { |id| tiles.key?(id) }

        text = ->(ids) { squash(ids.map { |id| tiles[id]["text_#{lang}"] }.join(" ")) }
        declared = ([ answer ] + check["accept"].to_a + check["errors"].to_a.map { |e| e["answer"] }).select { |s| s.is_a?(Array) && s.all? { |id| tiles.key?(id) } }.map { |s| text.call(s) }
        moved(answer, tiles, lang).map { |ids| text.call(ids) }.uniq - declared
      end

      # +remedy+: what the author may do about an order that is right (the lesson's check and the item's instance name their own `accept`).
      def message(orders, remedy: "accept it in `accept` if it is right, or declare the error")
        shown = orders.first(SHOWN).map(&:inspect).join(", ")
        "the sentence is built from tiles and the time or place phrase may stand elsewhere: #{shown}#{orders.size > SHOWN ? " (and #{orders.size - SHOWN} more)" : ''} " \
          "is neither the answer, nor accepted, nor a declared error: #{remedy}"
      end

      # The language of the tiles (en or es), nil for Italian tiles or a mix.
      def language(tiles)
        langs = tiles.flat_map { |t| t.keys & %w[text_en text_es] }.uniq
        langs.size == 1 ? langs.first.delete_prefix("text_") : nil
      end

      # The answer with each phrase moved alone: lists of ids, the answer itself left out.
      def moved(answer, tiles, lang)
        words = ->(id) { tiles[id]["text_#{lang}"].to_s.downcase.scan(/\p{L}+|\p{N}+/) }
        out = []
        i = 0
        while i < answer.size
          unless PHRASE[lang].include?(words.call(answer[i]).first)
            i += 1
            next
          end
          j = i
          j += 1 while j < answer.size - 1 && words.call(answer[j]).all? { |w| LINK[lang].include?(w) }
          run = answer[i..j]
          rest = answer[0...i] + answer[(j + 1)..]
          unless run.size == answer.size || rest.size < 2 || words.call(answer[j]).all? { |w| LINK[lang].include?(w) }
            [ 0, rest.size, i - 1, i - 2, i + 1 ].uniq.select { |at| at.between?(0, rest.size) && at != i }.each { |at| out << (rest[0...at] + run + rest[at..]) }
          end
          i = j + 1
        end
        out
      end

      def squash(text) = text.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, " ").strip
    end
  end
end
