# Which student's data the teacher's page shows (D-217). Everything that means "the student" means
# the official one by default; `?student=KEY` picks a trial student. The key is validated against
# the rows that exist: an unknown key is a 404, never a guess.
module ViewedStudent
  extend ActiveSupport::Concern

  included do
    before_action :require_known_student_param
    helper_method :viewed_student, :student_choices, :student_label, :student_name, :student_dative, :student_param
  end

  # The student whose data the page shows; nil before the official student's first login.
  def viewed_student
    return @viewed_student if defined?(@viewed_student)

    key = params[:student].to_s
    @viewed_student = key.empty? ? Student.official : Student.find_by(key: key, kind: "student")
  end

  # The query parameter that keeps the choice in links: nil for the official student.
  def student_param
    student = viewed_student
    student && !student.official? ? { student: student.key } : {}
  end

  # The official student and the trial students that exist, to choose from; only when there is a choice.
  def student_choices
    @student_choices ||= Student.real.then { |all| all.size > 1 ? all : [] }
  end

  def student_label(student)
    return I18n.t("teacher.student_picker.official") if student.official?

    I18n.t("teacher.student_picker.trial", name: Banco::EdgeProxy.student_map.key(student.key) || student.key)
  end

  # How the page names a student (D-217 map): the login mapped to the key in BANCO_STUDENT_USERS, the
  # operator's own word for the person. With no map: "lo studente" for the official student, the key for a trial one.
  def student_name(student)
    key = student&.key || Student::OFFICIAL_KEY
    login = Banco::EdgeProxy.student_map.key(key)
    return login if login
    key == Student::OFFICIAL_KEY ? I18n.t("teacher.student_picker.the_student") : key
  end

  # "a <name>" ("ad" before a name that starts with a), or "allo studente" when the map names nobody.
  def student_dative(student)
    login = Banco::EdgeProxy.student_map.key(student&.key || Student::OFFICIAL_KEY)
    return I18n.t("teacher.student_picker.to_the_student") unless login

    I18n.t(login.match?(/\Aa/i) ? "teacher.student_picker.to_login_a" : "teacher.student_picker.to_login", name: login)
  end

  private

  def require_known_student_param
    key = params[:student].to_s
    return if key.empty?

    head(:not_found) unless Student::KEY_FORMAT.match?(key) && Student.exists?(key: key, kind: "student")
  end
end
