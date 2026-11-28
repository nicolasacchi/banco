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
    #
    # E-TILE-ACCEPT-FORM (round 10, D-408): the tiles are text, and an order that the key or `accept` names is shown to the student as the sentence he built. A tile that
    # ends with `.`, `?` or `!` must be the last of every such order, and a tile that opens with a capital (the sentence's own: not «I», not a name or a word the
    # frequency lists do not know, which is a proper noun) must be the first: otherwise an accepted order reads «in the rain. When the bus arrived, we were waiting» or
    # «mi hermano está cansado Hoy», which is no sentence. The author writes the tiles without the sentence's capital and full stop, or keeps the tile in place
    # in every order. The capital counts only when the key opens with it: a capital in the middle of the key is a name.
    module TileOrder
      FINAL = /[.?!…][)"»”’']*\z/
      CAPITAL = /\A[¿¡"«“(]*\p{Lu}/
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
        form_problems(check).each_with_index { |problem, i| ctx.add("E-TILE-ACCEPT-FORM", "accept", problem, rule: "tile-accept-form-#{i}") }
        orders = orders(check)
        return if orders.empty?

        ctx.add("W-TILE-ORDER", "answer", message(orders), rule: "tile-order", orders: orders)
      end

      # The messages of E-TILE-ACCEPT-FORM for +check+ (same shape as +orders+): [] when every order that the key or `accept` names keeps its final-punctuation tile
      # last and the capital tile of the sentence first. One message for each tile and order, the key's first.
      def form_problems(check)
        tiles = check["tiles"].to_a.to_h { |t| [ t["id"], t ] }
        lang = language(tiles.values)
        key = Array(check["answer"])
        return [] unless lang && key.size >= 2 && key.all? { |id| tiles.key?(id) }

        text = ->(id) { tiles[id]["text_#{lang}"].to_s.strip }
        orders = [ key ] + check["accept"].to_a.select { |o| o.is_a?(Array) && o.size == key.size && o.all? { |id| tiles.key?(id) } }
        initial = key.first if text.call(key.first).match?(CAPITAL) && !proper_noun?(lang, text.call(key.first))
        orders.uniq.flat_map do |order|
          sentence = order.map(&text).join(" ")
          order.each_with_index.filter_map do |id, i|
            if text.call(id).match?(FINAL) && i < order.size - 1
              "the tile #{text.call(id).inspect} ends the sentence with a full stop, question mark or exclamation mark and must be the last tile of every order, but #{sentence.inspect} puts it " \
                "elsewhere: write the tiles without the final punctuation, or accept only orders that end with it"
            elsif id == initial && i.positive?
              "the tile #{text.call(id).inspect} opens the sentence with a capital and must be the first tile of every order, but #{sentence.inspect} puts it elsewhere: " \
                "write it in lower case (the student reads the built order as a sentence), or accept only orders that start with it"
            end
          end
        end.uniq
      end

      # A name or a word that the frequency lists do not know (Picasso, Malaga): the capital is the word's own, wherever it stands. «I» and «I'm» likewise.
      def proper_noun?(lang, tile_text)
        word = tile_text.scan(/\p{L}[\p{L}'’]*/).first.to_s
        return true if lang == "en" && word.match?(/\AI(?:['’]\p{L}+)?\z/)

        Validation::Bilingual.names(lang).include?(word.downcase) || !Lessons::Lexicon.known?(lang, word)
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
