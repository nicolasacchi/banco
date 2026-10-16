module Search
  # The latest revision of each object, per revision table: what the teacher's and the agents' doors show of a versioned thing
  # (older revisions are history). Read from the primary database at query time, never stored in the index.
  module Latest
    SOURCES = {
      "lesson_revisions" => [ LessonRevision, :lesson_id ],
      "topic_revisions" => [ TopicRevision, :lesson_id ],
      "item_revisions" => [ ItemRevision, :item_id ],
      "course_revisions" => [ CourseRevision, :subject_id ],
      "skill_graph_revisions" => [ SkillGraphRevision, :subject_id ]
    }.freeze

    module_function

    # {table => [ids]}
    def all = SOURCES.keys.to_h { |table| [ table, ids(table) ] }

    def ids(table)
      model, group = SOURCES.fetch(table)
      model.group(group).maximum(:id).values
    end
  end
end
