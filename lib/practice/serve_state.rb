# frozen_string_literal: true

module Practice
  # The serve state machine (A8.3), pure. A serve's state is derived from its tries, its hint and
  # solution events and the clock; nothing is stored. call derives the Status; step says what an
  # event does to it (table rows 1-15), so the recorder only writes what the step names.
  module ServeState
    V1 = Rules::V1

    Status = Data.define(:state, :closed_by, :w, :near_misses, :hints_shown, :solution_sent, :next_try_number, :actions)

    # result: :accept (write), :noop (nothing to write: invalid answer, repeated hint, solution again),
    # :closed (HTTP 409), :bad_hint (HTTP 422). closes_as: the closed_by the event causes. solution_reason:
    # the solution_shown reason to write. auto_hint: write the next hint with auto true (hint_n).
    Step = Data.define(:result, :closes_as, :solution_reason, :auto_hint, :hint_n)

    EVENTS = %i[answer hint solution_request].freeze
    ANSWER_OUTCOMES = (Outcome::OUTCOMES + [ :invalid ]).freeze

    module_function

    def call(serve:, tries:, events:, hints_total:, now:)
      tries = tries.sort_by(&:try_number)
      w = near = 0
      closed_by = nil
      tries.each do |t|
        break if closed_by

        case t.outcome.to_sym
        when :correct, :correct_aided then closed_by = :correct
        when :typical_error
          w += 1
          closed_by = :wrong
        when :unrecognised, :form
          w += 1
          closed_by = :wrong if w >= V1::MAX_WRONG_TRIES
        when :near_miss
          near += 1
          closed_by = :near_miss if near > V1::MAX_NEAR_MISS_RETRIES
        when :undetermined then closed_by = :undetermined
        else raise ArgumentError, "unknown outcome #{t.outcome.inspect}"
        end
      end
      solutions = events.select { |e| e.kind.to_s == "solution_shown" }
      closed_by ||= :solution if solutions.any? { |e| e.reason.to_s == "requested" }
      hints = events.select { |e| e.kind.to_s == "hint_shown" }.map(&:n).uniq.size
      state = if closed_by then :closed
      elsif now - serve_time(serve) > V1::OPEN_SERVE_HOURS * 3600 then :abandoned
      else :open
      end
      Status.new(state: state, closed_by: closed_by, w: w, near_misses: near, hints_shown: [ hints, hints_total.to_i ].min,
                 solution_sent: solutions.any?, next_try_number: state == :open ? tries.size + 1 : nil,
                 actions: actions(state, closed_by, tries.last, solutions))
    end

    def serve_time(serve) = serve.respond_to?(:at) ? serve.at : serve.created_at

    # A try is aided when a hint of the serve was shown, a W try exists on it, or the serve is a re-seen one.
    def aided?(reason:, w:, hints_shown:) = reason.to_s == "reseen" || w.to_i.positive? || hints_shown.to_i.positive?

    def actions(state, closed_by, last, solutions)
      return [] if state == :abandoned
      return open_actions(last) if state == :open

      case closed_by
      when :correct, :undetermined then %i[next back]
      when :near_miss then %i[after_solution next back]
      when :solution then %i[after_solution back]
      when :wrong then wrong_actions(last, solutions)
      end
    end

    def open_actions(last)
      return %i[show_solution] unless last

      last.outcome.to_sym == :near_miss ? %i[retry] : %i[retry show_solution]
    end

    # Row 2 (typical error at once, solution not sent yet), row 13 (after "Mostra la soluzione"), row 6.
    def wrong_actions(last, solutions)
      typical = last&.outcome&.to_sym == :typical_error
      return typical ? %i[prova_questo show_solution back] : %i[show_solution back] if solutions.empty?

      row6 = solutions.any? { |e| e.reason.to_s == "after_last_try" }
      row6 && typical ? %i[prova_questo after_solution back] : %i[after_solution back]
    end

    # What event does to a serve in status. outcome: the answer's outcome (Practice::Outcome, or :invalid).
    # hint_n: the n of a hint request. hints_total: how many hints the instance has.
    def step(status, event, outcome: nil, hint_n: nil, hints_total: 0)
      raise ArgumentError, "unknown event #{event.inspect}" unless EVENTS.include?(event)

      case event
      when :answer then answer_step(status, outcome, hints_total)
      when :hint then hint_step(status, hint_n, hints_total)
      else solution_step(status)
      end
    end

    def answer_step(status, outcome, hints_total)
      raise ArgumentError, "unknown outcome #{outcome.inspect}" unless ANSWER_OUTCOMES.include?(outcome&.to_sym)
      return result(:closed) unless status.state == :open
      return result(:noop) if outcome.to_sym == :invalid # row 10

      case outcome.to_sym
      when :correct, :correct_aided then result(:accept, closes_as: :correct, solution_reason: "after_correct") # rows 1, 5
      when :typical_error
        status.w.zero? ? result(:accept, closes_as: :wrong) : result(:accept, closes_as: :wrong, solution_reason: "after_last_try") # rows 2, 6
      when :unrecognised, :form then wrong_step(status, outcome.to_sym, hints_total)
      when :near_miss
        status.near_misses.zero? ? result(:accept) : result(:accept, closes_as: :near_miss, solution_reason: "after_last_try") # rows 7, 8
      when :undetermined then result(:accept, closes_as: :undetermined, solution_reason: "after_undetermined") # row 9
      end
    end

    # Rows 3, 4, 6.
    def wrong_step(status, outcome, hints_total)
      return result(:accept, closes_as: :wrong, solution_reason: "after_last_try") if status.w >= V1::MAX_WRONG_TRIES - 1

      auto = outcome == :unrecognised && status.hints_shown < hints_total
      result(:accept, auto_hint: auto, hint_n: auto ? status.hints_shown + 1 : nil)
    end

    # Row 11 (and an idempotent repeat of a hint already shown; row 15 when closed).
    def hint_step(status, n, hints_total)
      return result(:closed) unless status.state == :open
      return result(:bad_hint) unless n.is_a?(Integer) && n >= 1
      return result(:noop, hint_n: n) if n <= status.hints_shown
      return result(:accept, hint_n: n) if n == status.hints_shown + 1 && n <= hints_total

      result(:bad_hint)
    end

    # Rows 12, 13, 14, 15.
    def solution_step(status)
      case status.state
      when :open then result(:accept, closes_as: :solution, solution_reason: "requested")
      when :closed
        if status.solution_sent then result(:noop) # row 14
        elsif status.closed_by == :wrong then result(:accept, solution_reason: "after_wrong") # row 13
        else result(:closed)
        end
      else result(:closed)
      end
    end

    def result(kind, closes_as: nil, solution_reason: nil, auto_hint: false, hint_n: nil)
      Step.new(result: kind, closes_as: closes_as, solution_reason: solution_reason, auto_hint: auto_hint, hint_n: hint_n)
    end
  end
end
