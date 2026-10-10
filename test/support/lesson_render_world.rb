# Invented lesson/2 revisions for the render check (R4): the served-form fixtures of test/fixtures/lesson2/served,
# and variants whose data is unreadable (a label too long, a number line too dense, a table too wide).
module LessonRenderWorld
  SERVED = Rails.root.join("test/fixtures/lesson2/served")

  def render_subject! = Subject.find_by(key: "math") || Subject.create!(key: "math", name_it: "Matematica", position: 1)

  def served(name) = JSON.parse(File.read(SERVED.join("#{name}.json")))

  def store_lesson2!(body, key: "ripasso.math.render-#{SecureRandom.hex(3)}")
    lesson = Lesson.create!(subject: render_subject!, key: key, kind: "ripasso")
    md = "---\nkey: #{key}\n---\n"
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(body.merge("key" => key)),
                           rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  # A card appended to a copy of the body (n, level core), with the given blocks.
  def with_card(body, blocks, level: "core")
    copy = Marshal.load(Marshal.dump(body))
    n = copy["cards"].map { |c| c["n"] }.max + 1
    copy["cards"] << { "n" => n, "id" => "extra-#{n}", "role" => "idea", "level" => level, "title_it" => "Scheda di prova", "icon" => "lightbulb", "blocks" => blocks.each_with_index.map { |b, i| b.merge("n" => i + 1) } }
    copy
  end
end
