# The switch of the visual lesson layer (A10): BANCO_LESSON2_ENABLED, default on, read like
# BANCO_DECISIONS_ENABLED. At 0 a lesson/2 page is drawn in safe mode: the long column with the text, formulas,
# callouts, summary, mistakes, tables and the served example steps; diagrams and schemas replaced by their
# alt text and description; checks and step reveal off. The operator switches it with a container restart.
module Banco
  module Lesson2
    module_function

    def enabled? = ENV.fetch("BANCO_LESSON2_ENABLED", "1") != "0"
  end
end
