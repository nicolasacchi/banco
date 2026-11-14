# D-327: the public API. Tokens get an expiry and a teacher login, and two roles: bot_read (GET only) and teacher
# (the reads of bot_read plus decisions and comment actions). Comment events get the origin "api". api_tokens.role and
# comment_events.origin have CHECK constraints, and SQLite cannot change a constraint in place, so both tables are
# rebuilt as in AddExtraLessonKind: Rails copies the rows with their ids (api_token_revocations keeps its foreign key,
# checked below) and the append-only triggers are installed again on the new tables.
class AddPublicApiTokens < ActiveRecord::Migration[8.1]
  OLD_ROLES = "role IN ('agent_claude','agent_omp','ci')".freeze
  NEW_ROLES = "role IN ('agent_claude','agent_omp','ci','bot_read','teacher')".freeze
  TEACHER_LOGIN = "role <> 'teacher' OR (teacher_login IS NOT NULL AND length(teacher_login) > 0)".freeze
  OLD_ORIGINS = "origin IN ('web','console','student')".freeze
  NEW_ORIGINS = "origin IN ('web','console','api','student')".freeze

  def up
    add_column :api_tokens, :expires_at, :datetime
    add_column :api_tokens, :teacher_login, :string
    remove_check_constraint :api_tokens, OLD_ROLES, name: "api_tokens_role"
    add_check_constraint :api_tokens, NEW_ROLES, name: "api_tokens_role"
    add_check_constraint :api_tokens, TEACHER_LOGIN, name: "api_tokens_teacher_login"
    swap_origin(OLD_ORIGINS, NEW_ORIGINS)
    %i[api_tokens comment_events].each { |table| Banco::AppendOnly.install(connection, table) }
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "api events or tokens of the new roles may exist and the ledger is append-only"
  end

  private

  def swap_origin(from, to)
    remove_check_constraint :comment_events, from, name: "comment_events_origin"
    add_check_constraint :comment_events, to, name: "comment_events_origin"
  end
end
