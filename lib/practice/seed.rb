# frozen_string_literal: true

module Practice
  # A seed from the entry diagnosis (A8.6). state is a Practice::Rules::V1::STATES name (string);
  # implied marks a skill not assessed because a harder one was shown ("below_demonstrated").
  Seed = Data.define(:skill, :state, :at, :run_id, :implied) do
    def initialize(skill:, state:, at:, run_id:, implied: false) = super
  end
end
