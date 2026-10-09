require "yaml"

# The lesson/2 fixtures of R0 (test/fixtures/lesson2) and a deliberately crude splitter that turns a
# fixture's lesson.md into the body shape of banco.lesson/2, only so that the good fixtures can be
# checked against the schema before the real parser (Lessons::Parser2, R1) exists. It does no
# validation of its own and understands exactly the constructs of the fixtures; R1 replaces it.
module Lesson2Fixtures
  DIR = Rails.root.join("test/fixtures/lesson2")
  MANIFEST = JSON.parse(DIR.join("manifest.json").read)
  CONTEXT = JSON.parse(DIR.join("context.json").read)

  module_function

  def read(name) = DIR.join(name).read

  # The invented course of context.json as a Validation::Context (R1): the skills with their error codes, the
  # programme lines, the topics of the course map.
  def context(subject = "math")
    c = CONTEXT.fetch(subject)
    lines = c["source_lines"].to_h { |l| [ [ l["source"], l["line"] ], l["text"] ] }
    skills = c["skills"].to_h { |k| [ k, { "key" => k, "errors" => c["error_codes"].map { |code| { "code" => code } } } ] }
    Validation::Context.new(subject: subject, skill: ->(k) { skills[k] },
                            source_line: ->(s, n) { (t = lines[[ s, n ]]) && { text: t, origin: "pdf" } },
                            topic: ->(k) { c["topics"].include?(k) })
  end

  def check(text, subject = "math") = Validation::LessonChecks.call(text, subject: subject, context: context(subject))

  def front_matter(text) = YAML.safe_load(text[/\A---\n(.*?)\n---\n/m, 1])

  # A fence-aware read of the cards of +text+: [{ level:, role:, title:, tag_tokens:, line: }] and the part headings.
  def headings(text)
    depth = 0
    cards = []
    parts = []
    text.each_line.with_index(1) do |raw, n|
      l = raw.chomp
      if depth.zero? && (m = l.match(/\A## (?<title>.+?) \{(?<tag>[^{}]*)\}[ \t]*\z/))
        cards << { title: m[:title], tokens: m[:tag].split, line: n }
      elsif depth.zero? && l.start_with?("# ")
        parts << { title: l[2..], line: n }
      elsif l.match?(/\A:{3,4} \S/) then depth += 1
      elsif l.match?(/\A:{3,4}\z/) then depth -= 1
      end
    end
    [ cards, parts ]
  end

  def fences(text) = text.scan(/^(:{3,4}) ([a-z_]+)/).map(&:last)

  def body(text)
    front = front_matter(text)
    cards = []
    parts = []
    cur = nil
    blk = nil
    more = nil
    para = []
    target = -> { more ? more[:inner] : cur[:blocks] }
    flush = lambda do
      t = para.join("\n").strip
      target.call << { "type" => "text", "text_it" => t } unless t.empty?
      para = []
    end
    text.sub(/\A---\n.*?\n---\n/m, "").each_line do |line|
      l = line.chomp
      if blk
        if l == ":::"
          target.call << block(*blk[:kind], blk[:lines].join)
          blk = nil
        else
          blk[:lines] << line
        end
      elsif (m = l.match(/\A:::: (\w+)(?: "(.*)")?\z/))
        flush.call
        more = { title: m[2], inner: [] }
      elsif l == "::::"
        flush.call
        cur[:blocks] << { "type" => "more", "title_it" => more[:title], "blocks" => more[:inner] }
        more = nil
      elsif (m = l.match(/\A::: (\w+)(?: (\w+))?(?: "(.*)")?\z/))
        flush.call
        blk = { kind: [ m[1], m[2], m[3] ], lines: [] }
      elsif more.nil? && l.match?(/\A# /)
        flush.call if cur
        parts << { "n" => parts.size + 1, "title_it" => l[2..] }
      elsif more.nil? && (m = l.match(/\A## (?<title>.+?) \{(?<tag>[^{}]*)\}[ \t]*\z/))
        flush.call if cur
        toks = m[:tag].split
        cur = { n: cards.size + 1, role: toks.shift, level: "core", title: m[:title], blocks: [], part: parts.size, extra_tokens: {} }
        toks.each { |t| t == "extra" ? cur[:level] = "extra" : cur[:extra_tokens].store(*t.split("=", 2)) }
        cards << cur
      elsif l.strip.empty? then flush.call if cur
      else para << l
      end
    end
    flush.call
    front.merge("schema_version" => 2, "words" => { "core" => 0, "extra" => 0 }, "pages" => []).tap do |b|
      b["parts"] = parts unless parts.empty?
      b["cards"] = cards.map { |c| card(c) }
    end
  end

  def card(c)
    h = { "n" => c[:n], "id" => c[:extra_tokens]["id"] || "c#{c[:n]}", "role" => c[:role], "level" => c[:level], "title_it" => c[:title],
          "icon" => c[:extra_tokens]["icon"] || "lightbulb", "blocks" => number(c[:blocks]) }
    h["part"] = c[:part] if c[:level] == "core" && c[:part].positive?
    h["tone"] = c[:extra_tokens]["tone"] if c[:extra_tokens]["tone"]
    h
  end

  def number(blocks)
    blocks.each_with_index.map do |b, i|
      b = b.merge("n" => i + 1)
      b["blocks"] = number(b["blocks"]) if b["blocks"]
      b["exercises"] = b["exercises"].each_with_index.map { |e, k| e.merge("n" => k + 1) } if b["exercises"]
      b
    end
  end

  def block(type, arg, title, raw)
    data = case type
    when "callout", "summary" then { "text" => raw }
    when "math" then raw.include?("lines:") ? YAML.safe_load(raw) : { "tex" => raw.strip }
    else YAML.safe_load(raw) || {}
    end
    case type
    when "callout" then { "type" => "callout", "kind" => arg, "title_it" => title, "text_it" => data["text"].strip }.compact
    when "summary" then { "type" => "summary", "points_it" => data["text"].lines.map { |x| x.sub(/\A- /, "").strip } }
    when "math" then { "type" => "math" }.merge(data)
    when "diagram" then { "type" => "diagram", "diagram" => data.merge("type" => arg) }
    when "schema" then { "type" => "schema", "schema" => data.merge("type" => arg) }
    when "check" then data.merge("type" => "check", "component" => arg)
    else data.merge("type" => type).merge(title ? { "title_it" => title } : {})
    end
  end
end
