class SkillGraphRevision < ApplicationRecord
  belongs_to :subject
  belongs_to :author_session, class_name: "AgentSession", optional: true
end
