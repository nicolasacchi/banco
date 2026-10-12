# frozen_string_literal: true

module Lessons
  module Diagrams
    # insolation (T5, W2-1, D-275): the Earth's profile with parallel rays on up to four latitudes and, with `stepper`, one movable beam
    # (-80 to 80 degrees, every 10). The same beam of light covers 1/cos(latitude - subsolar latitude) times the ground; that number is
    # computed here and in the browser, printed with one decimal, never written by the author. `subsolar` is the latitude where the Sun
    # is overhead (0 at an equinox, 23,4 on 21 June, -23,4 on 21 December). Browser twin: lesson/diagrams/maps/insolation.js.
    module Insolation
      extend Contract

      GF = GeoFormat
      MAX_ANGLE = 85            # degrees from the subsolar latitude: beyond it the Sun is nearly on the horizon
      TROPIC = Rational(235, 10) # the largest subsolar latitude
      STEP = 10                 # the movable beam goes from -80 to 80 degrees every STEP
      STEP_RANGE = (-80..80)

      module_function

      def n(text) = Diagrams.num(text)

      def sub_of(eff) = n(eff["subsolar"] || "0") || Rational(0)

      def spread(lat, sub) = 1.0 / Math.cos((lat - sub).to_f * Math::PI / 180)

      def spread_str(lat, sub) = GF.fmt1f(spread(lat, sub))

      # The latitudes the movable beam can stand on in a state with subsolar latitude +sub+.
      def stepper_values(sub) = STEP_RANGE.step(STEP).select { |v| (v - sub).abs <= MAX_ANGLE }

      def stepper?(eff) = eff["stepper"] == true

      def spread_on?(eff) = eff["spread"] != false

      def state(eff, c, path)
        sub = n(eff["subsolar"] || "0")
        c.diagram("#{path}/subsolar", "the Sun is overhead between the tropics: subsolar goes from -23,5 to 23,5", rule: "subsolar#{path}") if sub.nil? || sub.abs > TROPIC
        sub ||= Rational(0)
        lats = eff["latitudes"].to_a.map { |l| n(l) }
        lats.each_with_index do |lat, i|
          at = "#{path}/latitudes/#{i}"
          if lat.nil? || lat.abs > 90
            c.diagram(at, "a latitude goes from -90 to 90", rule: "lat#{at}")
          elsif (lat - sub).abs > MAX_ANGLE
            c.diagram(at, "at #{GF.lat_word(lat)} the Sun is more than #{MAX_ANGLE} degrees from overhead (subsolar #{GF.lat_word(sub)}): the beam would graze the ground", rule: "lat-low#{at}")
          end
        end
        c.diagram("#{path}/latitudes", "a latitude is listed twice", rule: "lat-dup#{path}") if lats.compact.uniq.size != lats.compact.size
      end

      def effective(data, state)
        top = data.reject { |k, _| k == "states" }
        sts = data["states"].is_a?(Array) && data["states"].any? ? data["states"] : nil
        sts ? top.merge(sts[[ state, sts.size - 1 ].min]) : top
      end

      # Where the movable beam starts: 0, else the nearest step to 0 that no fixed beam stands on (the two would be drawn over one another);
      # on a tie the northern one.
      def start_beam(eff)
        values = stepper_values(sub_of(eff))
        taken = eff["latitudes"].to_a.map { |l| n(l) }
        free = values.reject { |v| taken.include?(v) }
        pool = free.any? ? free : values
        pool.min_by { |v| [ v.abs, -v ] } || Rational(0)
      end

      # The value of the movable beam in a state: the control's, kept on a legal step; the start when none.
      def beam_of(eff, controls)
        values = stepper_values(sub_of(eff))
        want = controls && controls["lat"] ? Rational(controls["lat"].to_i) : start_beam(eff)
        values.include?(want) ? want : (values.min_by { |v| (v - want).abs } || Rational(0))
      end

      def sentence(lat, sub, moving: false)
        "#{moving ? 'Il raggio mobile' : 'Il raggio'} a #{GF.lat_word(lat)}: la luce si spalma su #{spread_str(lat, sub)} volte il terreno."
      end

      def sun_phrase(sub) = sub.zero? ? "l'equatore" : GF.lat_word(sub)

      def describe(data, state: 0, controls: nil, **)
        eff = effective(data, state)
        sub = sub_of(eff)
        lats = eff["latitudes"].to_a.map { |l| n(l) }
        out = [ "La Terra vista di lato, con i raggi del Sole paralleli. Il Sole è alto sopra #{sun_phrase(sub)}." ]
        lats.each { |lat| out << (spread_on?(eff) ? sentence(lat, sub) : "C'è un raggio a #{GF.lat_word(lat)}.") }
        if stepper?(eff)
          beam = beam_of(eff, controls)
          out << (spread_on?(eff) ? sentence(beam, sub, moving: true) : "Il raggio mobile è a #{GF.lat_word(beam)}.")
        end
        out << "#{eff['op_it']}." if eff["op_it"]
        out.join(" ")
      end

      def printed(data, state = 0)
        eff = effective(data, state)
        sub = sub_of(eff)
        lats = eff["latitudes"].to_a.map { |l| n(l) }
        out = [ describe(data, state: state) ]
        lats.each { |lat| out << GF.lat_word(lat) }
        lats.each { |lat| out << spread_str(lat, sub) } if spread_on?(eff)
        out << eff["op_it"] if eff["op_it"]
        out << data["caption_it"] if data["caption_it"]
        out.compact.uniq
      end

      # The movable beam's readouts (the latitude and its spread) in every state, and each fixed spread.
      def reachable(data)
        out = []
        states = data["states"].is_a?(Array) && data["states"].any? ? data["states"].each_index.map { |i| effective(data, i) } : [ effective(data, 0) ]
        states.each do |eff|
          sub = sub_of(eff)
          eff["latitudes"].to_a.each { |l| (lat = n(l)) && out << spread_str(lat, sub) }
          next unless stepper?(eff)

          stepper_values(sub).each { |v| out << GF.lat_word(v) << spread_str(v, sub) }
        end
        out.uniq.then { |all| all.size > Contract::REACHABLE_CAP ? :over_cap : all }
      end

      def served(data, mode: :student, **) = StudentBody.diagram_generic(data)

      def targets(_data, set) = raise(ArgumentError, "insolation has no select targets (#{set.inspect})")
    end
  end
end
