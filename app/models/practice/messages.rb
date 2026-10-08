module Practice
  # The Italian sentences the student reads from the practice engine (A8.2, A9.4). Every sentence is an
  # approved stored text chosen by code (firm rule 1): the locale file, the item's error catalogue and
  # FORM_IT. Nothing is generated.
  module Messages
    # The checker's form violations (and the fraction ones) as a sentence for the student.
    FORM_IT = {
      "lowest_terms" => "La frazione si può ancora semplificare: riducila ai minimi termini.",
      "not_lowest_terms" => "La frazione si può ancora semplificare: riducila ai minimi termini.",
      "improper" => "Scrivi la frazione come numero misto, come chiede la consegna.",
      "mixed" => "Scrivi la frazione senza parte intera, come chiede la consegna.",
      "denominator_one" => "Se il denominatore è 1, scrivi solo il numeratore.",
      "sign_in_denominator" => "Il segno va davanti alla frazione, non al denominatore.",
      "not_rationalized" => "Il denominatore non deve contenere radici: razionalizza.",
      "radicand_not_reduced" => "Puoi ancora portare qualcosa fuori dalla radice.",
      "factor_not_extracted" => "Puoi ancora portare un fattore fuori dalla radice.",
      "radicand_not_multiplied" => "Moltiplica i numeri sotto la stessa radice.",
      "roots_not_multiplied" => "Riunisci le radici in una sola.",
      "like_radicals_not_combined" => "Somma i radicali simili.",
      "like_terms_not_combined" => "Somma i termini simili.",
      "coefficients_not_multiplied" => "Moltiplica i coefficienti numerici.",
      "common_factor_not_cancelled" => "C'è ancora un fattore comune da semplificare.",
      "not_fully_factored" => "La scomposizione non è completa: si può scomporre ancora.",
      "common_factor_not_extracted" => "Raccogli prima il fattore comune.",
      "not_expanded" => "Svolgi i prodotti e scrivi il risultato senza parentesi.",
      "monomial_not_reduced" => "Il monomio si può ancora ridurre.",
      "zero_term" => "Togli i termini uguali a zero.",
      "trivial_root" => "La radice si può calcolare: scrivi il numero.",
      "nested_root" => "Riduci le radici dentro altre radici.",
      "fraction_under_root" => "Non lasciare una frazione sotto la radice.",
      "scientific_notation" => "Scrivi il numero in notazione scientifica.",
      "leading_zeros" => "Scrivi anche gli zeri iniziali richiesti."
    }.freeze

    module_function

    # The sentence of an answer's outcome. typical: the catalogue message of the first error code
    # (nil when the item has none). closing: the serve ends with this answer after a wrong try, so a
    # non-typical failure says "second_wrong" (rows 6 and 8 of the state machine).
    def feedback(outcome, typical: nil, violations: [], closing: false)
      case outcome.to_sym
      when :correct then I18n.t("practice.correct")
      when :correct_aided then I18n.t("practice.correct_aided")
      when :typical_error then typical.presence || I18n.t("practice.unrecognised")
      when :unrecognised then closing ? I18n.t("practice.second_wrong") : I18n.t("practice.unrecognised")
      when :form then closing ? I18n.t("practice.second_wrong") : form(violations)
      when :near_miss then closing ? I18n.t("practice.second_wrong") : I18n.t("practice.near_miss")
      when :undetermined then I18n.t("practice.undetermined")
      end
    end

    def form(violations)
      FORM_IT[Array(violations).first] || I18n.t("practice.form")
    end

    # An extra line with a credit: the accents note or the form message of a declared form skill.
    def note(evidence_key, violations: [])
      case evidence_key.to_s
      when "orthography_slip" then I18n.t("practice.accents_note")
      when "wrong_form_declared" then form(violations)
      end
    end

    def state_it(state) = I18n.t("states.#{state}")

    # The "perché" sentence of a SkillState's why = {code:, ...}.
    def why_it(why)
      why = why.dup
      code = why.delete(:code)
      why[:date] = why[:date].strftime("%d/%m/%Y") if why[:date].respond_to?(:strftime)
      why[:previous] = state_it(why[:previous]).downcase if why[:previous]
      I18n.t("why.#{code}", **why)
    end

    def reason_it(reason)
      case reason.to_s
      when "prova_questo" then I18n.t("practice.try_this_reason")
      when "reseen" then I18n.t("practice.reseen")
      when "after_solution" then I18n.t("practice.after_solution")
      end
    end
  end
end
