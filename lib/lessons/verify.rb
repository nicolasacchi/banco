# frozen_string_literal: true

module Lessons
  # Truth at authoring time (WAVE2 1.10, D-268): a check may declare `verify: {fn: "chrono.duration", args: {from: "-133", to: "-27"}}`.
  # Ruby calls the registered function and refuses the check (E-LESSON-VERIFY) when its `answer` differs from the value, or when an
  # errors[] entry carries a `code` that the function knows as a mutant (its typical wrong values, by name) and the entry's answer
  # differs from the mutant's value. Grading at run time is unchanged (Grading::Closed); the field is dropped from the served body (L1).
  #
  # Where a function comes from, in this order:
  #   1. Verify.register(name, mutants: nil) { |args| value }   what a test or a track registers explicitly;
  #   2. the figure types: Lessons::Diagrams::TYPE.verify_functions -> {"seats.threshold" => callable};
  #   3. the domain libraries (LIBRARIES): "chrono.duration" calls Lessons::Chrono.duration with the arguments named as the frozen
  #      signature names them (SIGNATURES): positional ones in order, `base:` style ones as keywords. A result that is a Hash or an
  #      Array is read through the reserved argument `pick` ("digits", or an index; `element` is the same key for chem.count); mutants come from Lib.mutants(*the same arguments).
  # `program.*` functions are not Ruby's: they are checked by the render check in the server's Chrome (firm rule 3).
  module Verify
    LIBRARIES = {
      "chrono" => "Chrono", "dates" => "Dates", "numwords" => "NumWords", "money" => "Money", "chem" => "Chem",
      "words" => "Words", "verbs" => "Verbs", "bits" => "Bits"
    }.freeze
    # integer-looking arguments of the libraries' integer parameters
    INTEGER_PARAMS = %w[width base n days rows cols].freeze

    Function = Data.define(:call, :mutants)
    Problem = Data.define(:path, :message)

    @registry = {}

    class << self
      attr_reader :registry

      def register(name, mutants: nil, &fn)
        @registry[name.to_s] = Function.new(call: fn, mutants: mutants)
      end

      def reset! = @registry.clear
    end

    module_function

    # The Function for +name+, or nil.
    def resolve(name)
      name = name.to_s
      return nil if name.start_with?("program.")
      return registry[name] if registry.key?(name)

      from_figures(name) || from_library(name)
    end

    def from_figures(name)
      Diagrams::TYPES.each_value do |const|
        mod = Diagrams.const_get(const)
        next unless mod.respond_to?(:verify_functions)

        found = mod.verify_functions[name]
        return (found.is_a?(Function) ? found : Function.new(call: found, mutants: nil)) if found
      end
      nil
    end

    def from_library(name)
      lib, fn = name.split(".", 2)
      const = LIBRARIES[lib] or return nil
      mod = Lessons.const_get(const)
      signature = mod.const_defined?(:SIGNATURES) ? mod::SIGNATURES[fn] : nil
      return nil unless signature && mod.respond_to?(fn)

      params = signature[/\((.*)\)/m, 1].to_s.split(",").map(&:strip)
      names = params.reject { |p| p.include?(":") }.map { |p| p.delete_suffix("?") }
      keywords = params.select { |p| p.include?(":") }.map { |p| p.split(":").first }
      build = lambda do |args|
        positional = names.map { |n| coerce(n, args.fetch(n) { raise ArgumentError, "the argument #{n} is missing" }) }
        keyword = keywords.filter_map { |k| [ k.to_sym, coerce(k, args[k]) ] if args.key?(k) }.to_h
        [ positional, keyword ]
      end
      call = lambda do |args|
        positional, keyword = build.call(args)
        result = mod.public_send(fn, *positional, **keyword)
        # chem.count without an element is all the atoms of the formula, coefficient included (a number, as a check answers a number)
        result = result.values.sum if lib == "chem" && fn == "count" && result.is_a?(Hash) && (args["pick"] || args["element"]).nil?
        pick(result, args["pick"] || args["element"])
      end
      mutants = if mod.respond_to?(:mutants) && fn == "duration"
        lambda do |args|
          positional, keyword = build.call(args)
          mod.mutants(*positional, **keyword)
        end
      end
      Function.new(call: call, mutants: mutants)
    end

    def coerce(name, value)
      INTEGER_PARAMS.include?(name) && value.to_s.match?(/\A-?\d+\z/) ? value.to_i : value
    end

    def pick(result, key)
      case result
      when Hash then key ? result.fetch(key.to_s) { result[key.to_sym] } : result
      when Array then key ? result.fetch(key.to_i) : result
      else result
      end
    end

    # The problems [Problem] of one check's verify field; [] when it holds (or there is none).
    def problems(check)
      spec = check["verify"] or return []
      name = spec["fn"].to_s
      return [] if name.start_with?("program.") # the render check's business

      fn = resolve(name)
      return [ Problem.new("verify/fn", "no function #{name.inspect} is registered") ] unless fn

      args = spec["args"].to_h { |k, v| [ k.to_s, v ] }
      begin
        value = text(fn.call.call(args))
      rescue NotImplementedError => e
        return [ Problem.new("verify", "#{name} is not built yet: #{e.message}") ]
      rescue StandardError => e
        return [ Problem.new("verify/args", "#{name} cannot be computed from these arguments (#{e.class}: #{e.message})") ]
      end
      out = []
      right = expected(check)
      out << Problem.new("answer", "the answer #{right.inspect} differs from #{name}(#{args.map { |k, v| "#{k}: #{v}" }.join(', ')}) = #{value.inspect}") unless same?(value, right)
      out.concat(mutant_problems(check, fn, name, args))
      out
    end

    def mutant_problems(check, fn, name, args)
      return [] unless fn.mutants && check["errors"].to_a.any? { |e| e["code"] }

      table = fn.mutants.call(args).to_h { |k, v| [ k.to_s, text(v) ] }
      check["errors"].each_with_index.filter_map do |e, i|
        next unless e["code"] && table.key?(e["code"].to_s)
        next if same?(text(e["answer"]), table[e["code"].to_s])

        Problem.new("errors/#{i}/answer", "the error #{e['code']} is the mutant #{table[e['code'].to_s].inspect} of #{name}, not #{e['answer'].inspect}")
      end
    rescue NotImplementedError
      []
    rescue StandardError => e
      [ Problem.new("verify/args", "#{name} has no mutants for these arguments (#{e.class}: #{e.message})") ]
    end

    # What the check's answer says as text: a number, a fraction or text; a choice's right option text.
    def expected(check)
      case check["component"]
      when "choice" then check["options"].to_a.find { |o| o["id"] == check["answer"] }&.fetch("text_it", nil).to_s
      else text(check["answer"])
      end
    end

    def text(value) = value.is_a?(String) ? value : (value.is_a?(Numeric) ? value.to_s : (value.respond_to?(:to_str) ? value.to_str : value.to_s))

    def same?(a, b)
      cmp = Num.compare(a.to_s, b.to_s)
      return cmp.zero? if cmp

      a.to_s.strip.downcase == b.to_s.strip.downcase
    end
  end
end
