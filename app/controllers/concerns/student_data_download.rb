# One download of a student's data (D-360): the zip of Privacy::StudentExport, sent as an attachment, with the one append-only app
# event `data_export` (who and when) written after the file is built. Used by the student's own /privacy/data and the teacher's
# /teacher/students/:key/data; nothing else is written and the file is never cached.
module StudentDataDownload
  extend ActiveSupport::Concern

  private

  def send_student_data(student, by:, login: nil)
    export = Privacy::StudentExport.new(student)
    data = export.zip
    Privacy::StudentExport.record!(student, by: by, login: login)
    response.headers["Cache-Control"] = "no-store"
    send_data data, type: "application/zip", filename: export.filename, disposition: "attachment"
  end
end
