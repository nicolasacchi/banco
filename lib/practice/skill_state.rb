# frozen_string_literal: true

module Practice
  # The derived state of one skill (A8.5). why = {code:, ...parameters} (Practice::Messages turns it into text).
  SkillState = Data.define(:skill, :state, :since, :demonstrated_at, :consolidated_at, :seed, :counts, :why) do
    # What the entry test showed and nothing since moved (D-378): demonstrated by the diagnosis seed, never studied. The student reads «Già sapevi».
    def known? = !seed.nil? && seed.state.to_s == "demonstrated" && state == "demonstrated" && since == seed.at
  end
end
