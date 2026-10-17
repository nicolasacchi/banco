module Teacher
  # "Prova come studente" (D-309): the teacher walks the student's site as a student. The pages are the student's own
  # controllers under /teacher/preview (route default preview: true); this one holds the entry test list, the view
  # switch and the reset. The preview student is a student row of kind preview; whatever it does is its own log and
  # never reaches a report, the Cruscotto, the comments, the search answers or the API (they read kind student).
  class PreviewsController < ApplicationController
    include ActingStudent

    # The entry test list (the old "Prova come S" page), reached from Oggi in the preview.
    def index
      @subjects = Subject.order(:position).select { |s| Diagnosis::Conductor.latest_blueprint(s) }
    end

    # «Come lo vede S» (official) or «Con le bozze» (drafts); kept in the session, never in the address.
    def view
      session[:preview_view] = params[:view].to_s if PREVIEW_VIEWS.include?(params[:view].to_s)
      redirect_back_to_preview
    end

    # «Ricomincia da capo»: a new preview student, so a clean slate; the old rows stay (append-only).
    def reset
      Student.reset_preview!
      redirect_back_to_preview(notice: I18n.t("teacher.preview.reset_done"), home: true)
    end

    private

    # Only a preview address of this site is a place to go back to; anything else lands on the preview home.
    def redirect_back_to_preview(notice: nil, home: false)
      back = params[:back].to_s
      safe = back.match?(%r{\A/teacher/preview(/[A-Za-z0-9_./-]*)?(\?[A-Za-z0-9_=&%.+-]*)?\z}) && !back.include?("//") && !back.include?("/runs/")
      redirect_to((safe && !home) ? back : PREVIEW_ROOT, status: :see_other, notice: notice)
    end
  end
end
