# The subject of a /subjects/:subject route (the course formats of Phase 1b) and the brief row every open answer carries.
module SubjectScoped
  private

  def load_subject
    @subject = Subject.find_by(key: params[:subject].to_s)
    refuse("E-NOT-FOUND", "subject", "no subject #{params[:subject].to_s.first(40).inspect}", "banco status", 404) unless @subject
  end

  def brief_row(name)
    brief = Brief.find(name) or return nil
    { name: brief.name, version: brief.version, sha256: brief.sha256 }
  end
end
