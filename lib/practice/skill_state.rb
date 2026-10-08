# frozen_string_literal: true

module Practice
  # The derived state of one skill (A8.5). why = {code:, ...parameters} (Practice::Messages turns it into text).
  SkillState = Data.define(:skill, :state, :since, :demonstrated_at, :consolidated_at, :seed, :counts, :why)
end
