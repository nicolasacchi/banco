# frozen_string_literal: true

# Who is the user? Only the edge proxy (Traefik, after Authelia) can say, and
# only on the web listener (D-02).
#
# Remote-User / Remote-Groups are accepted when request.remote_addr (the TCP
# peer) is inside BANCO_EDGE_PROXY AND the request arrived on the web listener.
# request.remote_ip is never used: it trusts a forged X-Forwarded-For. The
# headers are read raw with get_header so a client header can never shadow them
# through another Rack key.
module EdgeTrust
  extend ActiveSupport::Concern

  TEACHER_GROUP = "banco-teacher"
  STUDENT_GROUP = "banco-student"
  GUEST_GROUP = "banco-guest"

  # Three roles (D-217): the teacher acts, the guest only reads, the student answers. A login in the
  # teacher list with the teacher group is a teacher whatever else it carries; a guest is in the guest
  # group, in BANCO_GUEST_USERS and not a teacher.
  Identity = Struct.new(:login, :groups, keyword_init: true) do
    def teacher?
      groups.include?(TEACHER_GROUP) && Banco::EdgeProxy.teacher_users.include?(login)
    end

    def guest?
      groups.include?(GUEST_GROUP) && Banco::EdgeProxy.guest_users.include?(login) && !teacher?
    end

    # Someone who may read the teacher's pages.
    def reader? = teacher? || guest?

    # In the student group and neither teacher nor guest, whether or not the login is configured.
    def student_group? = groups.include?(STUDENT_GROUP) && !teacher? && !guest?

    # A student the operator has configured. With BANCO_STUDENT_USERS unset, any student login is the
    # official student (staging and old setups); with it set (even if a pair is bad) only the listed logins are students.
    def student?
      student_group? && (!Banco::EdgeProxy.student_map_configured? || Banco::EdgeProxy.student_map.key?(login))
    end

    # In the student group, but the map is set and does not list the login.
    def unconfigured_student? = student_group? && !student?

    def student_key
      return nil unless student?

      map = Banco::EdgeProxy.student_map
      Banco::EdgeProxy.student_map_configured? ? map.fetch(login) : Student::OFFICIAL_KEY
    end

    def trial_student? = student? && student_key != Student::OFFICIAL_KEY
  end

  included do
    rescue_from MalformedRemoteUser do
      render plain: "Bad request", status: :bad_request
    end
  end

  class MalformedRemoteUser < StandardError; end

  def edge_trusted?
    request.env[Banco::ListenerTag::TAG_KEY] == :web && Banco::EdgeProxy.include?(request.remote_addr)
  end

  # nil when the request does not come from the trusted edge or carries no
  # Remote-User. A Remote-User containing a comma means the header was
  # duplicated on its way: 400.
  def current_identity
    return @current_identity if defined?(@current_identity)

    @current_identity = build_identity
  end

  private

  def build_identity
    return nil unless edge_trusted?

    login = request.get_header("HTTP_REMOTE_USER").to_s.strip
    return nil if login.empty?
    raise MalformedRemoteUser if login.include?(",")

    groups = request.get_header("HTTP_REMOTE_GROUPS").to_s.split(",").map(&:strip).reject(&:empty?)
    Identity.new(login: login, groups: groups)
  end
end
