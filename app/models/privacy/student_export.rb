require "erb"

module Privacy
  # Everything banco holds about one student, as ONE zip (D-360; GDPR art. 15, access, and art. 20, portability): a README.txt and a
  # riepilogo.html in Italian, `student.json`, `preferences.json` and one JSON file (an array of objects) per table that has his rows.
  # The tables are the ones of db/structure.sql that carry a `student_id` or hang from one that does (TABLES); every other table is
  # classed in NOT_EXPORTED with the reason, and test/models/privacy/student_export_test.rb fails when a table is in neither list, so a
  # new student table cannot be forgotten.
  #
  # Read-only: it selects, builds strings and writes nothing. The caller records the one append-only app event `data_export`
  # (`record!`): who and when. A student's file holds his rows only; never another student's (every scope starts from his id), never a
  # token or a secret, never an address of another person (the teacher's and the bots' network addresses, user agents and request
  # ids are dropped), never an answer key or a solution of an item (an item he was shown is named by its key and revision).
  class StudentExport
    EVENT_KIND = "data_export".freeze
    BY = %w[student teacher console].freeze

    # file: the JSON file's name (default: the table's); scope: student -> relation; drop: columns left out; describe: the README line.
    Table = Struct.new(:name, :file, :scope, :drop, :description_it, keyword_init: true) do
      def path = "#{file || name}.json"
    end

    mine = ->(model) { ->(student) { model.where(student_id: student.id) } }
    runs = ->(student) { DiagnosisRun.where(student_id: student.id).select(:id) }
    run_events = ->(student) { DiagnosisEvent.where(diagnosis_run_id: runs.call(student)).select(:id) }
    attempts = ->(student) { Attempt.where(student_id: student.id).select(:id) }
    practice_attempts = ->(student) { PracticeAttempt.where(student_id: student.id).select(:id) }
    comments = ->(student) { Comment.where(student_id: student.id).select(:id) }
    # The teacher's own marks on a decision (where from, with what) are not his data; who decided is.
    decision_private = %w[remote_addr user_agent request_id groups request_path].freeze

    TABLES = [
      Table.new(name: "students", file: "student", scope: ->(student) { Student.where(id: student.id) }, drop: [],
                description_it: "chi sei per banco: il nome utente, il tipo di account (studente o prova) e quando è stato creato."),
      Table.new(name: "diagnosis_runs", scope: mine.call(DiagnosisRun), drop: %w[seed_salt],
                description_it: "i test d'ingresso che hai cominciato, uno per materia."),
      Table.new(name: "diagnosis_events", scope: ->(student) { DiagnosisEvent.where(diagnosis_run_id: runs.call(student)) }, drop: [],
                description_it: "che cosa è successo in ogni test d'ingresso, passo per passo: domande mostrate, risposte date, domande lasciate, pause, fine del test."),
      Table.new(name: "item_served", scope: ->(student) { ItemServed.where(diagnosis_event_id: run_events.call(student)) }, drop: [],
                description_it: "le domande del test d'ingresso come te le abbiamo mostrate: il nome dell'esercizio, la materia e l'ordine delle risposte."),
      Table.new(name: "attempts", scope: mine.call(Attempt), drop: [],
                description_it: "le tue risposte al test d'ingresso, con l'ora."),
      Table.new(name: "attempt_gradings", scope: ->(student) { AttemptGrading.where(attempt_id: attempts.call(student)) }, drop: [],
                description_it: "come è stata corretta ogni risposta del test d'ingresso."),
      Table.new(name: "grade_proposals", scope: ->(student) { GradeProposal.where(attempt_id: attempts.call(student)) },
                drop: %w[agent_session_id brief_sha256],
                description_it: "i punteggi che l'assistente del docente ha proposto per le tue risposte scritte, prima che il docente decidesse."),
      Table.new(name: "decisions", scope: mine.call(Decision), drop: decision_private,
                description_it: "le decisioni del docente che ti riguardano: il consenso, le correzioni delle tue risposte, la chiusura del test d'ingresso, l'apertura del corso. Di ognuna c'è chi l'ha presa e quando."),
      Table.new(name: "app_events", scope: mine.call(AppEvent), drop: [],
                description_it: "le cose che banco ha annotato su di te: le scelte in Impostazioni, le risposte rifiutate perché non valide, i promemoria mostrati prima di un esercizio, le risposte segnalate, e ogni volta che hai scaricato i tuoi dati."),
      Table.new(name: "practice_serves", scope: mine.call(PracticeServe), drop: %w[seed],
                description_it: "gli esercizi che ti sono stati proposti, con la lezione, l'abilità e il perché ti è stato proposto."),
      Table.new(name: "practice_attempts", scope: mine.call(PracticeAttempt), drop: [],
                description_it: "le tue prove negli esercizi: che cosa hai risposto, quando, e se avevi aperto un aiuto."),
      Table.new(name: "practice_gradings", scope: ->(student) { PracticeGrading.where(practice_attempt_id: practice_attempts.call(student)) }, drop: [],
                description_it: "come è stata corretta ogni prova degli esercizi (comprese le correzioni del docente)."),
      Table.new(name: "practice_events", scope: mine.call(PracticeEvent), drop: [],
                description_it: "gli aiuti e le soluzioni che hai aperto negli esercizi, e le lezioni che hai aperto dagli esercizi."),
      Table.new(name: "practice_drafts", scope: mine.call(PracticeDraft), drop: [],
                description_it: "le bozze di risposta che banco ha tenuto mentre scrivevi, prima dell'invio."),
      Table.new(name: "practice_contests", scope: mine.call(PracticeContest), drop: [],
                description_it: "le volte che hai segnalato che una correzione non ti convinceva."),
      Table.new(name: "practice_pool_exhaustions", scope: mine.call(PracticePoolExhaustion), drop: [],
                description_it: "le volte in cui gli esercizi di un'abilità sono finiti."),
      Table.new(name: "student_questions", scope: mine.call(StudentQuestion), drop: [],
                description_it: "le tue domande «Non ho capito», con la pagina in cui le hai fatte."),
      Table.new(name: "lesson_events", scope: mine.call(LessonEvent), drop: [],
                description_it: "che cosa hai fatto nelle lezioni: schede viste, controlli (con le tue prove), parti aperte."),
      Table.new(name: "comments", scope: mine.call(Comment), drop: [],
                description_it: "i commenti che hai scritto, con la pagina, le parole che avevi selezionato, la grandezza dello schermo e il tema."),
      Table.new(name: "comment_events", scope: ->(student) { CommentEvent.where(comment_id: comments.call(student)) }, drop: %w[request_id],
                description_it: "che cosa è successo a ogni commento: le risposte del docente, quando è stato letto, chiuso o riaperto, le tue risposte e quando ne hai cancellato uno (i commenti cancellati ci sono ancora). Il tuo indirizzo di rete c'è solo nelle righe scritte da te."),
      Table.new(name: "ratings", scope: mine.call(Rating), drop: [],
                description_it: "le stelle e i commenti che hai dato agli esercizi e alle lezioni, con l'esercizio o la lezione e la versione che avevi davanti.")
    ].freeze

    # Tables that are not about a student, with why: the export test needs every table of the schema in TABLES or here.
    NOT_EXPORTED_BY_REASON = {
      "the course and its items are the same for every student, they hold nothing about him" => %w[
        subjects syllabus_sources syllabus_lines reference_texts skill_graph_revisions items item_revisions item_instances blueprint_revisions
        lessons lesson_revisions course_revisions topic_revisions pages page_revisions page_files speech_clips],
      "the authoring ledger of the content agents and its checks: about the content, never about a student" => %w[
        item_validations item_renders item_reviews blind_solves review_findings finding_responses finding_assessments lesson_reviews
        lesson_renders lesson_finding_responses page_validations page_reviews agent_sessions agent_session_corrections],
      "access of the bots and of view links: tokens and links, never a student's" => %w[
        api_tokens api_token_renewals api_token_revocations view_links view_link_redemptions view_link_revocations],
      "the framework's own bookkeeping" => %w[ar_internal_metadata schema_migrations]
    }.freeze
    NOT_EXPORTED = NOT_EXPORTED_BY_REASON.flat_map { |reason, names| names.map { |name| [ name, reason ] } }.to_h.freeze

    # The columns that name a catalogue row by number get a readable sibling, so the file says which exercise or lesson he was shown.
    READABLE = {
      "subject_id" => ->(lookup, id) { { "subject_key" => lookup.subject_key(id) } },
      "item_instance_id" => ->(lookup, id) { lookup.item_of_instance(id) },
      "item_revision_id" => ->(lookup, id) { lookup.item_of_revision(id) },
      "topic_revision_id" => ->(lookup, id) { { "lesson_key" => lookup.lesson_of_topic(id) } },
      "lesson_revision_id" => ->(lookup, id) { { "lesson_key" => lookup.lesson_of_revision(id) } }
    }.freeze

    attr_reader :student

    def self.table_names = TABLES.map(&:name)

    # The append-only app event of a download: who (student, teacher with the login, console with the operating-system user) and when.
    def self.record!(student, by:, login: nil)
      raise ArgumentError, "by is one of #{BY.join(', ')}" unless BY.include?(by.to_s)

      payload = { by: by.to_s }
      payload[:login] = login.to_s if login.present?
      AppEvent.create!(kind: EVENT_KIND, student: student, payload_json: payload.to_json)
    end

    def initialize(student, now: Time.current)
      raise ArgumentError, "the preview student has no export" unless student.kind == "student"

      @student = student
      @now = now.utc
    end

    # { "attempts" => [row, ...], ... } for every table, empty ones included.
    def tables
      @tables ||= TABLES.to_h { |table| [ table.name, rows_of(table) ] }
    end

    def counts = tables.transform_values(&:size)

    def preferences
      @preferences ||= begin
        history = AppEvent.where(kind: Diagnosis::Preferences::KIND, student_id: student.id).order(:id).map do |event|
          { "at" => event.created_at.utc.iso8601(6) }.merge(JSON.parse(event.payload_json.to_s.presence || "{}"))
        end
        current = Diagnosis::Preferences.for(student).merge(Diagnosis::Preferences.lesson(student))
                                        .merge(language: Diagnosis::Preferences.language(student)).stringify_keys
        { "current" => current, "history" => history }
      end
    end

    # { file name => content } in the order they sit in the zip.
    def files
      @files ||= begin
        out = { "README.txt" => readme, "riepilogo.html" => summary_html }
        out["preferences.json"] = json(preferences)
        TABLES.each { |table| out[table.path] = json(tables.fetch(table.name)) }
        out
      end
    end

    def zip = ZipWriter.build(files.to_a, time: @now)

    # banco-dati-<key>-<date>.zip
    def filename = "banco-dati-#{student.key}-#{@now.strftime('%Y-%m-%d')}.zip"

    def readme
      lines = []
      lines << "I dati di banco su #{student.key}"
      lines << "=" * lines.first.size
      lines << ""
      lines << "Questa cartella compressa è la copia di tutto quello che banco ha su di te. L'hai chiesta tu (diritto di accesso e di portabilità, articoli 15 e 20 del GDPR)."
      lines << "È stata creata il #{@now.strftime('%d/%m/%Y alle %H:%M')} (ora di Greenwich: in Italia è 1 ora in più, 2 d'estate)."
      lines << "Scaricarla non cambia niente: banco ne tiene solo una riga («data_export») con chi l'ha scaricata e quando."
      lines << ""
      lines << "Da dove cominciare"
      lines << "- riepilogo.html: si apre con il browser. Dice quante cose ci sono di ogni tipo e di quando sono."
      lines << "- I file .json sono elenchi: ogni riga è una cosa successa (una risposta, un commento...). Si aprono con un editor di testo, con il browser o con un foglio di calcolo. Se un elenco è vuoto, vuol dire che non c'è niente."
      lines << "- Le date sono scritte così: 2026-11-18T14:03:00.000000Z (anno, mese, giorno, ora)."
      lines << "- I campi che finiscono per _key dicono il nome della materia, dell'esercizio o della lezione."
      lines << ""
      lines << "I file"
      lines << "- preferences.json: i colori, la grandezza dei testi, la lingua e le altre scelte di Impostazioni: quelle di adesso («current») e tutte le volte che le hai cambiate («history»)."
      TABLES.each { |table| lines << "- #{table.path}: #{table.description_it}" }
      lines << ""
      lines << "Che cosa non c'è, e perché"
      lines << "- I dati di altre persone: questa copia è solo tua."
      lines << "- Le risposte giuste e le soluzioni degli esercizi che non hai visto: non sono dati su di te."
      lines << "- Le password: banco non le ha mai (le tiene il portale di accesso)."
      lines << "- Chiavi e segreti del programma, e gli indirizzi di rete e i dati del computer del docente."
      lines << "- Il cookie del dispositivo: sta solo nel tuo browser e dice soltanto «computer dello studente». Non contiene un numero tuo e banco non lo salva."
      lines << "- Le parole che cerchi: banco non le conserva."
      lines << "- I registri del server (log): non sono in banco. Per averli: chiedi al titolare (vedi la pagina Privacy)."
      lines << ""
      lines << "Cose che puoi chiedere: correggere un dato, cancellarlo, o smettere di usarlo. Vedi la pagina Privacy."
      lines.join("\n") << "\n"
    end

    def summary_html
      h = ERB::Util.method(:html_escape)
      rows = TABLES.map do |table|
        records = tables.fetch(table.name)
        next if records.empty?

        "<tr><td><code>#{h.call(table.path)}</code></td><td>#{records.size}</td><td>#{h.call(span_of(records))}</td><td>#{h.call(kinds_of(records))}</td></tr>"
      end.compact
      <<~HTML
        <!doctype html>
        <html lang="it"><head><meta charset="utf-8"><title>I tuoi dati in banco</title>
        <style>body{font-family:sans-serif;max-width:50rem;margin:2rem auto;padding:0 1rem;line-height:1.5}table{border-collapse:collapse;width:100%}td,th{border:1px solid #888;padding:.3rem .5rem;text-align:left;vertical-align:top}</style></head>
        <body>
        <h1>I tuoi dati in banco</h1>
        <p>Utente: <strong>#{h.call(student.key)}</strong>. Copia creata il #{@now.strftime('%d/%m/%Y alle %H:%M')} (ora di Greenwich).</p>
        <p>#{h.call(total_line)}</p>
        #{rows.empty? ? '<p>Non c&rsquo;&egrave; ancora niente.</p>' : "<table>\n<tr><th>File</th><th>Righe</th><th>Date</th><th>Di che tipo</th></tr>\n#{rows.join("\n")}\n</table>"}
        <p>Che cosa è ogni file lo dice <code>README.txt</code>.</p>
        </body></html>
      HTML
    end

    private

    def total_line
      total = counts.values.sum
      total.zero? ? "Non abbiamo ancora righe che ti riguardano." : "In tutto #{total} righe, in #{counts.count { |_, n| n.positive? }} file."
    end

    # "dal 2026-11-01 al 2026-11-18" over created_at.
    def span_of(records)
      days = records.filter_map { |row| row["created_at"]&.first(10) }
      return "" if days.empty?

      first, last = days.minmax
      first == last ? "il #{first}" : "dal #{first} al #{last}"
    end

    # "hint_shown: 3, solution_shown: 1" over the rows' kind, when the table has one.
    def kinds_of(records)
      return "" unless records.first.key?("kind")

      records.map { |row| row["kind"] }.tally.sort_by { |kind, n| [ -n, kind.to_s ] }.map { |kind, n| "#{kind}: #{n}" }.join(", ")
    end

    def json(value) = JSON.pretty_generate(value) << "\n"

    def rows_of(table)
      table.scope.call(student).order(:id).map { |record| row_of(table, record) }
    end

    def row_of(table, record)
      row = {}
      record.attributes.each do |column, value|
        next if table.drop.include?(column)

        if column.end_with?("_json")
          row[column.delete_suffix("_json")] = parse(value)
        else
          row[column] = value.respond_to?(:utc) ? value.utc.iso8601(6) : value
        end
        extra = READABLE[column]&.call(lookup, value) unless value.nil?
        row.merge!(extra) { |_, kept, _| kept } if extra
      end
      finish(table, record, row)
    end

    # The rows that need more than a column list: who decided and how (not from where), and an address only where it is his own.
    def finish(table, record, row)
      case table.name
      when "decisions"
        row["via"] = record.via
        row["payload"].delete("token") if row["payload"].is_a?(Hash)
      when "comment_events"
        row.delete("remote_addr") unless record.origin == "student"
      end
      row
    end

    def parse(text)
      return nil if text.nil?

      JSON.parse(text)
    rescue JSON::ParserError
      text
    end

    def lookup = @lookup ||= Lookup.new

    # Keys of the catalogue rows a column points to; cached per id, so a long log costs a few queries.
    class Lookup
      def initialize = @cache = Hash.new { |hash, name| hash[name] = {} }

      def subject_key(id) = cached(:subject, id) { Subject.where(id: id).pick(:key) }

      def item_of_instance(id)
        cached(:instance, id) do
          key, seq = ItemInstance.joins(item_revision: :item).where(id: id).pick("items.key", "item_revisions.seq")
          { "item_key" => key, "item_revision" => seq }
        end
      end

      def item_of_revision(id)
        cached(:revision, id) do
          key, seq = ItemRevision.joins(:item).where(id: id).pick("items.key", "item_revisions.seq")
          { "item_key" => key, "item_revision" => seq }
        end
      end

      def lesson_of_topic(id) = cached(:topic, id) { TopicRevision.joins(:lesson).where(id: id).pick("lessons.key") }

      def lesson_of_revision(id) = cached(:lesson_revision, id) { LessonRevision.joins(:lesson).where(id: id).pick("lessons.key") }

      private

      def cached(name, id)
        store = @cache[name]
        store.key?(id) ? store[id] : (store[id] = yield)
      end
    end
  end
end
