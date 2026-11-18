# The spoken clips of the lessons (D-359): GET /speech/clips/<key>.mp3, a file made ahead of time by SpeakLessonRevisionJob and named by the SHA-256
# of its recipe (Speech::Key), so the answer never changes: cached for a year. For the student, the preview, the teacher and the guest (it is course
# material, like the page posters); on the view listener too, for the teacher's pages a view link shows. Nothing is recorded and nothing is made here:
# a key that has no file is a 404 (the browser then falls back to an accepted device voice, or skips the segment). Byte ranges are answered, because
# Safari asks for them before it plays a file.
class SpeechClipsController < ApplicationController
  RANGE = /\Abytes=(\d*)-(\d*)\z/

  before_action :require_identity!

  def show
    file = Speech::Clips.path(params[:key])
    return head(:not_found) unless file && File.file?(file)

    bytes = File.binread(file)
    response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
    response.headers["Accept-Ranges"] = "bytes"
    response.headers["X-Content-Type-Options"] = "nosniff"
    range = byte_range(bytes.bytesize)
    return head(:range_not_satisfiable, "Content-Range" => "bytes */#{bytes.bytesize}") if range == :unsatisfiable

    if range
      response.headers["Content-Range"] = "bytes #{range.first}-#{range.last}/#{bytes.bytesize}"
      send_data bytes.byteslice(range), type: "audio/mpeg", disposition: "inline", status: :partial_content
    else
      send_data bytes, type: "audio/mpeg", disposition: "inline"
    end
  end

  private

  def require_identity!
    head :forbidden unless current_identity&.student? || current_identity&.reader?
  end

  # The one byte range asked for (a Range of offsets), nil when none is asked (or a form this does not answer: the whole file then),
  # :unsatisfiable when it lies beyond the file.
  def byte_range(size)
    match = request.headers["Range"].to_s.strip.match(RANGE) or return nil
    first, last = match[1], match[2]
    return nil if first.empty? && last.empty?

    if first.empty? # the last N bytes
      n = last.to_i
      return :unsatisfiable if n.zero?

      return [ size - n, 0 ].max..(size - 1)
    end
    from = first.to_i
    return :unsatisfiable if from >= size

    to = last.empty? ? size - 1 : [ last.to_i, size - 1 ].min
    return :unsatisfiable if to < from

    from..to
  end
end
