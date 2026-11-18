# D-359: the server's spoken clips of the lessons («Ascolta»), made ahead of time by the TTS service from the segments a lesson revision says
# (never at the student's request, never in a request at all). One append-only row per clip stored under storage/speech_clips/<key[0,2]>/<key>.mp3:
# `key` is the lowercase hex SHA-256 of "<engine>|<voice>|<text>" (Speech::Key), so a changed text, voice or engine is a new clip and a row is never
# rewritten. The row says what the file is (engine, voice, language, size, duration when known); the file may be purged and made again, the row stays.
class CreateSpeechClips < ActiveRecord::Migration[8.1]
  def change
    create_table :speech_clips do |t|
      t.string :key, null: false
      t.string :engine, null: false
      t.string :voice, null: false
      t.string :lang, null: false
      t.integer :bytes, null: false
      t.integer :duration_ms
      t.datetime :created_at, null: false
      t.index :key, unique: true
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :speech_clips) }
    end
  end
end
