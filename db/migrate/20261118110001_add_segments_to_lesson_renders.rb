# D-359: the segments a lesson revision says aloud ([{lang, text, voice}], collected by the render check's host while it draws every card in every
# state), stored with the render row that found them (written once, with the row: lesson_renders stays append-only). Null on the rows made before this
# and on `error` rows; the verdict that counts for the audio is the latest passed one that has them (Speech::Plan).
class AddSegmentsToLessonRenders < ActiveRecord::Migration[8.1]
  def change
    add_column :lesson_renders, :segments_json, :text
  end
end
