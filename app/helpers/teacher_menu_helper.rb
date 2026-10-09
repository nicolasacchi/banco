# The teacher's persistent menu, the breadcrumb and the subject switcher (D-243). Pure navigation: no decisions here.
module TeacherMenuHelper
  SUBJECT_CONTROLLERS = %w[graphs tests courses topics reports item_plays items].freeze

  # The section of the menu this page belongs to: home, subjects, findings, corrections, students, preview or nil.
  def menu_section
    case controller_name
    when "teacher" then :home
    when *SUBJECT_CONTROLLERS then :subjects
    when "findings" then :findings
    when "corrections" then :corrections
    when "students", "practice" then :students
    when "previews" then :preview
    end
  end

  def menu_subjects = @menu_subjects ||= Subject.order(:position).to_a

  def blueprint_subject_ids = @blueprint_subject_ids ||= BlueprintRevision.distinct.pluck(:subject_id).to_set

  # The subject of the page, for the breadcrumb and the switcher: nil on the pages that belong to none.
  def page_subject = @subject || (@revision.item.subject if @revision.respond_to?(:item))

  # [[label, path or nil], ...] after "Cruscotto" and the subject name; the last has no path.
  def crumb_trail(subject)
    key = subject.key
    test = [ t("teacher.menu.test"), teacher_test_path(key: key) ]
    course = [ t("teacher.menu.course"), with_student(teacher_course_path(key: key)) ]
    case [ controller_name, action_name ]
    in [ "graphs", _ ] then [ [ t("teacher.menu.graph"), nil ] ]
    in [ "tests", "show" ] then [ [ t("teacher.menu.test"), nil ] ]
    in [ "tests", "all" ] then [ test, [ t("teacher.menu.all"), nil ] ]
    in [ "tests", "skill" ] then [ test, [ @row.label_it, nil ] ]
    in [ "courses", _ ] then [ [ t("teacher.menu.course"), nil ] ]
    in [ "topics", _ ] then [ course, [ @review.entry ? @review.entry["title_it"] : @review.key, nil ] ]
    in [ "reports", _ ] then [ [ t("teacher.menu.report"), nil ] ]
    in [ "practice", "show" ] then [ course, [ t("teacher.menu.practice"), nil ] ]
    in [ "practice", "skill" ] then [ course, [ t("teacher.menu.practice"), with_student(teacher_practice_path(key: key)) ], [ @row.label_it, nil ] ]
    in [ "item_plays", _ ] | [ "items", _ ] then [ test, [ t("teacher.menu.question"), nil ] ]
    else []
    end
  end

  # Where the same page of another subject is: pages about one skill, topic or question go to their parent page.
  def switch_path(subject)
    key = subject.key
    case [ controller_name, action_name ]
    in [ "graphs", _ ] then teacher_graph_path(key: key)
    in [ "tests", "all" ] then blueprint_subject_ids.include?(subject.id) ? teacher_test_all_path(key: key) : teacher_test_path(key: key)
    in [ "tests", _ ] | [ "item_plays", _ ] | [ "items", _ ] then teacher_test_path(key: key)
    in [ "courses", _ ] | [ "topics", _ ] then teacher_course_path(key: key)
    in [ "reports", _ ] then with_student(teacher_report_path(key: key))
    in [ "practice", _ ] then with_student(teacher_practice_path(key: key))
    else nil
    end
  end

  def menu_current(section) = menu_section == section ? { "aria-current": "page" } : {}
end
