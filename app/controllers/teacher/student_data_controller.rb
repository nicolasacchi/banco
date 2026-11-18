module Teacher
  # The same zip of a student's data as «Scarica i miei dati» (D-360), for the teacher: GET /teacher/students/:key/data. The teacher only
  # (a guest and a view link read the pages, they do not take a student's data out), the official student or a trial student by key
  # (the preview and an unknown key are a 404), web listener only. The only thing written is the app event `data_export` with the
  # teacher's login.
  class StudentDataController < Teacher::BaseController
    include StudentDataDownload

    skip_before_action :require_reader!
    before_action :require_teacher!

    def show
      student = Student.find_by(key: params[:key].to_s, kind: "student")
      return render_error(:not_found) unless student

      send_student_data(student, by: "teacher", login: current_identity.login)
    end
  end
end
