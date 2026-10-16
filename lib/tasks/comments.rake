namespace :banco do
  # The operator's console path to the student's comments (D-304). Never reachable over HTTP; the agents have no way to
  # read a comment. Reading needs no flag; writing is a dry run unless CONFIRM=1, needs BANCO_DECISIONS_ENABLED=1 and
  # TEACHER=<login from BANCO_TEACHER_USERS>, and is recorded with origin "console".
  #
  #   bin/rails banco:comments:list [STATE=sent|read|answered|closed] [REASON=..] [KIND=lesson|..] [SUBJECT=key] [WHO=official|trial] [TYPE=comment|question]
  #   bin/rails banco:comments:show ID=3
  #   bin/rails banco:comments:reply ID=3 TEACHER=<login> TEXT_IT="La risposta del docente." [CONFIRM=1]
  #   bin/rails banco:comments:resolve ID=3 TEACHER=<login> [REASON_IT="..."] [CONFIRM=1]
  #   bin/rails banco:comments:reopen ID=3 TEACHER=<login> [REASON_IT="..."] [CONFIRM=1]
  #   bin/rails banco:comments:read ID=3 TEACHER=<login> [CONFIRM=1]
  desc "List the student's comments (same as banco:comments:list)"
  task comments: "comments:list"

  namespace :comments do
    desc "List the student's comments: [STATE= REASON= KIND= SUBJECT= WHO= TYPE=]"
    task list: :environment do
      inbox = Comments::Inbox.new(state: ENV["STATE"], reason: ENV["REASON"], kind: ENV["KIND"], subject: ENV["SUBJECT"], who: ENV["WHO"], type: ENV["TYPE"])
      rows = inbox.rows
      puts "#{rows.size} row(s)"
      rows.each do |row|
        if row.type == :comment
          c = row.record
          puts format("comment %<id>d  %<state>-8s %<reason>-14s %<page>-9s %<who>s  %<at>s  %<text>s",
                      id: c.id, state: c.state, reason: c.reason, page: c.page_kind, who: c.trial ? "trial:#{c.student.key}" : "official",
                      at: c.created_at.strftime("%Y-%m-%d %H:%M"), text: c.text_it.to_s.first(60))
        else
          q = row.record
          puts format("question %<id>d  %<who>s  %<at>s  %<text>s", id: q.id, who: q.student.key, at: q.created_at.strftime("%Y-%m-%d %H:%M"), text: q.text_it.to_s.first(60))
        end
      end
    end

    desc "Show one comment with its place and history: ID="
    task show: :environment do
      comment = Comment.includes(:events, :student, :subject).find_by(id: ENV["ID"].to_s.to_i) or abort "no comment #{ENV['ID'].to_s.first(20).inspect} (ID= is required)"
      place = Comments::Place.new(comment)
      puts "comment #{comment.id}  state=#{comment.state}  reason=#{comment.reason}  #{comment.trial ? "trial student #{comment.student.key}" : 'official student'}"
      puts "page: #{comment.page_kind} #{comment.page_path}#{" (#{comment.subject.key})" if comment.subject}"
      puts "anchor: #{comment.anchor}" if comment.anchor
      puts "card: #{place.card.inspect}  block: #{place.block.inspect}" if comment.card
      puts "item revision: #{comment.item_revision_id}  instance: #{comment.item_instance_id}  serve: #{comment.practice_serve_id}  served event: #{comment.served_event_id}  run: #{comment.diagnosis_run_id}"
      puts "lesson revision: #{comment.lesson_revision_id}  topic revision: #{comment.topic_revision_id}  blueprint revision: #{comment.blueprint_revision_id}"
      puts "screen: #{comment.viewport_width}x#{comment.viewport_height}  theme: #{comment.theme}  size: #{comment.text_size}"
      puts "selected: #{comment.selected_text}" if comment.selected_text
      puts "text: #{comment.text_it || '(none)'}"
      comment.events.each { |e| puts "  #{e.created_at.strftime('%Y-%m-%d %H:%M')}  #{e.kind}  #{e.origin}  #{e.actor}#{"  #{e.text_it}" if e.text_it}" }
    end

    { reply: "Reply to a comment in the teacher's name: ID= TEACHER= TEXT_IT= [CONFIRM=1]",
      resolve: "Close a comment: ID= TEACHER= [REASON_IT=] [CONFIRM=1]",
      reopen: "Reopen a closed comment: ID= TEACHER= [REASON_IT=] [CONFIRM=1]",
      read: "Mark a comment as read: ID= TEACHER= [CONFIRM=1]" }.each do |action, description|
      desc description
      task action => :environment do
        teacher = ENV["TEACHER"].presence or abort "TEACHER=<login from BANCO_TEACHER_USERS> is required"
        id = ENV["ID"].presence or abort "ID= is required"
        result = Comments::Console.call(action: action, id: id, teacher: teacher, text_it: ENV["TEXT_IT"], reason: ENV["REASON_IT"], confirm: ENV["CONFIRM"] == "1")
        unless result.ok
          warn "refused: #{action} #{id}"
          result.errors.each { |e| warn "  - #{e}" }
          exit 1
        end
        puts result.recorded ? "recorded #{result.event.kind} on comment #{id} as #{teacher} via console" : "dry run, nothing written; add CONFIRM=1 to record #{action} on comment #{id}"
      end
    end
  end
end
