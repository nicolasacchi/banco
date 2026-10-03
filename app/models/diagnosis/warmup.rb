module Diagnosis
  # The warm-up, "prova dei comandi" (B-11): tasks from config/banco/warmup.yml,
  # graded here with the same graders as the diagnosis, with an immediate "riprova"
  # (it measures nothing), recorded in app_events as warmup_answer, warmup_completed
  # and, when the editor does not work for the student, warmup_editor_fallback.
  #
  # A task that is not the editor's repeats until it is right. An editor task
  # that is still wrong on the third try is skipped and the student's expression
  # items get a plain text field with a rendered echo (E-04, B-11).
  module Warmup
    CONFIG_PATH = Rails.root.join("config/banco/warmup.yml").freeze
    MAX_EDITOR_TRIES = 3

    module_function

    def tasks
      @tasks ||= YAML.safe_load_file(CONFIG_PATH, aliases: false).fetch("tasks").freeze
    end

    def task(id) = tasks.find { |t| t["id"] == id.to_s }

    # What the browser gets: no answers and no accept lists.
    def public_tasks
      tasks.map do |t|
        t.slice("id", "component", "prompt_it", "display", "accents", "editor")
      end
    end

    # right, or false. raw is in the encodings of D-030.
    def right?(task, raw)
      case task["component"]
      when "dont_know" then raw == Grading::DONT_KNOW_RAW
      when "pause" then raw == "done"
      when "expression" then task["accept"].map { |a| normalize(a) }.include?(normalize(raw))
      else closed_right?(task, raw)
      end
    end

    def closed_right?(task, raw)
      spec = Grading::Spec.from_hash(task.slice("component", "answer", "display"))
      Grading.grade_spec(spec, raw, source: "text").verdict == "correct"
    rescue StandardError
      false
    end

    def normalize(text) = text.to_s.gsub(/\\left|\\right|\s+/, "")

    # Records one answer. Returns "right", "retry" or "skip".
    def answer!(student, task_id, raw)
      task = task(task_id)
      return "retry" unless task

      ok = right?(task, raw.to_s)
      log(student, "warmup_answer", "task" => task["id"], "ok" => ok)
      return "right" if ok
      return "retry" unless task["editor"]

      failures = events_since_start(student, "warmup_answer").count do |e|
        p = JSON.parse(e.payload_json)
        p["task"] == task["id"] && !p["ok"]
      end
      return "retry" if failures < MAX_EDITOR_TRIES

      log(student, "warmup_answer", "task" => task["id"], "skipped" => true)
      log(student, "warmup_editor_fallback", "task" => task["id"]) unless fallback?(student)
      "skip"
    end

    # Ids of the tasks done in the current round.
    def done_ids(student)
      events_since_start(student, "warmup_answer").filter_map do |e|
        p = JSON.parse(e.payload_json)
        p["task"] if p["ok"] || p["skipped"]
      end.uniq
    end

    def complete?(student) = AppEvent.where(student_id: student.id, kind: "warmup_completed").exists?

    def fallback?(student) = AppEvent.where(student_id: student.id, kind: "warmup_editor_fallback").exists?

    # Writes warmup_completed when every task of the round is done.
    def complete!(student)
      return false unless (tasks.map { |t| t["id"] } - done_ids(student)).empty?

      log(student, "warmup_completed")
      true
    end

    # A round starts after the last warmup_completed.
    def events_since_start(student, kind)
      done = AppEvent.where(student_id: student.id, kind: "warmup_completed").maximum(:id) || 0
      AppEvent.where(student_id: student.id, kind: kind).where("id > ?", done)
    end

    def log(student, kind, payload = nil)
      AppEvent.create!(kind: kind, student: student, payload_json: payload&.to_json)
    end
  end
end
