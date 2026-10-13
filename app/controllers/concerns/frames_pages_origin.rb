# The two pages that may frame the free pages' origin (D-289, SPEC B4): the student's lesson page and the teacher's pages that hold the box.
# Every other page keeps frame-src 'none'. Done on a clone of the request's policy, so no other request sees it.
module FramesPagesOrigin
  extend ActiveSupport::Concern

  included { before_action :allow_pages_frames }

  private

  def allow_pages_frames
    policy = request.content_security_policy
    return unless policy

    request.content_security_policy = policy.clone.tap { |p| p.frame_src Pages.origin }
  end
end
