module Practice
  # The sentences the student reads from the practice engine (A8.2, A9.4), in the language of his page (D-356). Every sentence is an
  # approved stored text chosen by code (firm rule 1): the locale files (course.*.yml, grading.*.yml) and the item's error
  # catalogue, which is course content and stays Italian. Nothing is generated.
  module Messages
    module_function

    # The sentence of an answer's outcome. typical: the catalogue message of the first error code
    # (nil when the item has none). closing: the serve ends with this answer after a wrong try, so a
    # non-typical failure says "second_wrong" (rows 6 and 8 of the state machine).
    # near: :typo or :one_word (Grading::NearText.kind, practice/3) words a near miss; nil is the grader's own near miss (a spelling policy).
    def feedback(outcome, typical: nil, violations: [], closing: false, hint: true, near: nil)
      unrecognised = I18n.t(hint ? "practice.unrecognised" : "practice.unrecognised_no_hint")
      case outcome.to_sym
      when :correct then I18n.t("practice.correct")
      when :correct_aided then I18n.t("practice.correct_aided")
      when :typical_error then typical.presence || unrecognised
      when :unrecognised then closing ? I18n.t("practice.second_wrong") : unrecognised
      when :form then closing ? I18n.t("practice.second_wrong") : form(violations)
      when :near_miss then closing ? I18n.t("practice.second_wrong") : near_miss(near)
      when :contested then I18n.t("practice.contested")
      when :undetermined then I18n.t("practice.undetermined")
      end
    end

    def near_miss(near)
      case near&.to_sym
      when :typo then I18n.t("practice.near_typo")
      when :one_word then I18n.t("practice.near_one_word")
      else I18n.t("practice.near_miss")
      end
    end

    # The note under a right answer written as a whole sentence around the blank: only the words in place of ___ were asked.
    def full_sentence_note(part) = I18n.t("practice.full_sentence_note", part: part)

    # The checker's form violations (and the fraction ones) as a sentence (grading.form.*); the generic one for a violation without its own.
    def form(violations)
      violation = Array(violations).first
      violation ? I18n.t("grading.form.#{violation}", default: :"practice.form") : I18n.t("practice.form")
    end

    # An extra line with a credit: the accents note or the form message of a declared form skill.
    def note(evidence_key, violations: [], pair_note: nil)
      case evidence_key.to_s
      when "nearly_correct" then pair_note
      when "orthography_slip" then I18n.t("practice.accents_note")
      when "wrong_form_declared" then form(violations)
      end
    end

    def state_it(state) = I18n.t("states.#{state}")

    # Corrections without help counted toward demonstration (0..3), only while the skill is "in studio"; nil otherwise.
    def clean_count(why) = why[:code].to_s == "in_study" ? why[:n].to_i.clamp(0, 3) : nil

    # The "perché" sentence of a SkillState's why = {code:, ...}.
    def why_it(why)
      why = why.dup
      code = why.delete(:code)
      why[:date] = why[:date].strftime("%d/%m/%Y") if why[:date].respond_to?(:strftime)
      why[:previous] = state_it(why[:previous]).downcase if why[:previous]
      I18n.t("why.#{code}", **why)
    end

    # What a skill still needs to be demonstrated (practice/5 section 5: 3 distinct exercises right without help, 2 of them hard
    # to guess), read from the fold's why: {exercises:, long:, more_long:} or nil when nothing is missing.
    #   exercises: new right exercises needed (the larger of the 3 in all and the 2 hard to guess); long: how many of them hard to guess;
    #   more_long: true when the hard ones are asked on top of the plain count.
    # A skill not begun, or only seeded to recover or to learn, lacks everything; demonstrated, consolidated and «da ripassare» lack nothing here.
    def missing(why)
      case why[:code].to_s
      when "in_study" then done, low = why[:n].to_i, why[:low].to_i
      when "not_seen", "seed_to_recover", "seed_to_learn" then done = low = 0
      else return nil
      end
      need = [ Rules::V5::DEMONSTRATE_CORRECT_UNAIDED - done, 0 ].max
      need_long = [ Rules::V5::DEMONSTRATE_MIN_LOW_GUESS - low, 0 ].max
      return nil if need.zero? && need_long.zero?

      { exercises: [ need, need_long ].max, long: need_long, more_long: need.positive? && need_long.positive? }
    end

    # The sentences of what is missing, as one text; nil when nothing is missing.
    def missing_it(why)
      gap = missing(why) or return nil
      only_long = gap[:long].positive? && !gap[:more_long] # the count is met; only the hard ones are lacking
      lines = [ I18n.t(only_long ? "practice.missing.long" : "practice.missing.exercises", count: gap[:exercises]) ]
      lines << I18n.t("practice.missing.long_among", count: gap[:long]) if gap[:more_long]
      lines.join(" ")
    end

    # The one line of Oggi's «Riprendi» card for a topic: the most useful thing missing across its skills. entries: [[skill label, why], ...].
    # The skill nearest to done comes first; nil when nothing is missing.
    def close_line(entries)
      gaps = entries.filter_map { |label, why| (gap = missing(why)) && [ label, gap ] }
      label, gap = gaps.min_by { |_, g| g[:exercises] }
      I18n.t("today.close_line.exercises", skill: label, count: gap[:exercises]) if gap
    end

    # The page's line when the served exercise is the same item as the one before (Practice::Repeat, D-348).
    def same_item_it = I18n.t("practice.same_item", n: Rules::V5::ADVANCE_AFTER_CORRECT_UNAIDED)

    def reason_it(reason)
      case reason.to_s
      when "prova_questo" then I18n.t("practice.try_this_reason")
      when "reseen" then I18n.t("practice.reseen")
      when "after_solution" then I18n.t("practice.after_solution")
      end
    end
  end
end
