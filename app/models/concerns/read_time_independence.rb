# Independence of a review or a blind solve, derived when it is read (D-316): the session that filed it runs, by its
# TRUE model (AgentSession#model, which a correction can change), on another model than every author of what it
# reviewed. A row that is not independent does not count for any gate (Review::Gate, Approval::TopicGate,
# Approval::BlueprintGate, Pages::Validations.gate_reason) and the teacher's pages mark it «non indipendente»;
# its findings stay (they are observations) and stay listed. The rule is Providers.independent?.
module ReadTimeIndependence
  extend ActiveSupport::Concern

  # What was reviewed, for ItemSessions.for: an Item, a Lesson or a Page.
  def reviewed_thing = raise(NotImplementedError)

  def independent? = Providers.counting([ self ], reviewed_thing).any?
end
