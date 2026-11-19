# «I miei schemi» (D-372): where the schema of a topic is and whether it is open, for the pages that link to it (a subject's list of topics,
# the topic page, Oggi, and later the end of a topic's practice). One way to build the address, so the preview keeps to /teacher/preview.
module SchemasHelper
  # The address of the schema of a topic: the route helper of the student's pages (`spath`, D-309).
  def schema_href(topic_key) = spath("/topics/#{topic_key}/schema")

  # The address of the list «I miei schemi».
  def schemas_href = spath("/schemas")

  # Has this student opened the schema of the topic (the topic is done)? The preview opens every schema.
  def schema_open?(topic) = course_schemas.unlocked?(topic)

  def course_schemas = @_course_schemas ||= Course::Schemas.new(course_view, open_all: preview?)
end
