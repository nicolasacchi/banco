module Practice
  # «Same exercise again» (D-348): the selector keeps the student on an item until it has ADVANCE_AFTER_CORRECT_UNAIDED right tries without help,
  # and after a solution offers a similar instance of it, so the student can see the same kind of exercise several times in a row and think the page
  # is stuck. This says when that is what happens: the serve is of the same item as the previous serve of the skill and the item has fewer of those
  # tries than the rule needs. Read-only; nothing is stored.
  module Repeat
    NEEDED = Rules::V6::ADVANCE_AFTER_CORRECT_UNAIDED

    module_function

    # serve: a PracticeServe. true when the page should say so.
    def call(serve)
      skill = serve.skill_key
      input = Loader.for(serve.student, subject: Subject.find_by!(key: skill.split(".").first), skill: skill, seeds: false)
      me = input.serves.find { |row| row.id == serve.id } or return false
      previous = input.serves.select { |row| row.id < me.id }.max_by(&:id)
      return false unless previous && previous.item_id == me.item_id

      input.tries.count { |t| t.item_id == me.item_id && t.evidence == :C && !t.aided && !t.reseen } < NEEDED
    end
  end
end
