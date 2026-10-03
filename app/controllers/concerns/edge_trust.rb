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

  Identity = Struct.new(:login, :groups, keyword_init: true) do
    def teacher?
      groups.include?(TEACHER_GROUP) && Banco::EdgeProxy.teacher_users.include?(login)
    end

    def student?
      groups.include?(STUDENT_GROUP) && !teacher?
    end
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
