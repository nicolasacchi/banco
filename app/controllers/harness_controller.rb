# The harness listener (port 3200, internal): the page and the files Chrome loads to
# run an agent's generator or verify (A-02). It is a plain ActionController::API:
# no session, no cookie, no CSRF token, nothing of the app's own is reachable from
# the page. The run token in the address is the only capability.
class HarnessController < ActionController::API
  before_action :harden_headers

  # GET /h/:token/:file
  def show
    payload = Validation::Harness.verify(params[:token])
    return head :not_found unless payload

    name = params[:file]
    text =
      if Validation::Harness::PAGES.include?(name) then Validation::Harness.file(name)
      elsif Validation::Harness::MODULES.include?(name) then Validation::Harness.source(payload, name)
      end
    return head :not_found unless text

    response.set_header("Content-Security-Policy", Validation::Harness::CSP) if name == "harness.html"
    send_data text, type: Validation::Harness.content_type(name), disposition: "inline"
  end

  # GET /h/:token/lesson-render.html: the render host of a lesson/2 revision (token kind lrev). Our template and our
  # scripts only; the body is the student's projection of the stored one, drawn by the same modules and CSS.
  def lesson
    kind, id = Validation::Harness.verify(params[:token])
    return head :not_found unless kind == "lrev"

    revision = LessonRevision.find_by(id: id)
    return head :not_found unless revision&.lesson2?

    texts = Object.new.extend(LessonPagesHelper)
    html = ApplicationController.render(template: "harness/lesson_render", layout: false,
                                        assigns: { body: Lessons::StudentBody.for(revision, seed: "preview"), theme: params[:theme].to_s == "dark" ? "dark" : "cream",
                                                   config: { labels: texts.lesson2_texts, items: texts.lesson2_item_texts, minPx: Validation::Rules.get(:lesson2, :render, :min_text_px) } })
    hashes = html.scan(%r{<script(?![^>]*\bsrc=)(?![^>]*application/json)[^>]*>(.*?)</script>}m).map { |(code)| "'sha256-#{Base64.strict_encode64(Digest::SHA256.digest(code))}'" }
    response.set_header("Content-Security-Policy", format(Validation::Harness::LESSON_CSP, hashes: hashes.join(" ")))
    send_data html, type: "text/html; charset=utf-8", disposition: "inline"
  end

  # GET /h/:token/page-host.html and page-host.mjs: the host page of a free page validation (token kind prev). Our page and our script;
  # the frame source is fixed here from the stored revision (the validation mount of the pages app, with the kit asked for).
  def page_host
    kind, id = Validation::Harness.verify(params[:token])
    return head :not_found unless kind == "prev"

    revision = PageRevision.find_by(id: id)
    return head :not_found unless revision

    if params[:file] == "page-host.mjs"
      return send_data Validation::Harness.file("page_host.mjs"), type: "text/javascript; charset=utf-8", disposition: "inline"
    end

    kit = params[:kit].to_s
    return head :not_found unless Pages::Kit.released?(kit)

    src = Pages.shell_url(revision.bundle_sha256, kit, base: Pages.validation_origin)
    src += "?nowebgl=1" if params[:nowebgl].to_s == "1"
    h = ERB::Util.method(:html_escape)
    html = %(<!doctype html><html lang="it"><head><meta charset="utf-8"><title>page host</title><style>html,body{margin:0;background:#fff}</style></head>) +
           %(<body><div id="stage" data-src="#{h.call(src)}" data-min-height="#{revision.manifest['min_height'].to_i}"></div><script type="module" src="page-host.mjs"></script></body></html>)
    response.set_header("Content-Security-Policy", format(Validation::Harness::PAGE_HOST_CSP, origin: Pages.validation_origin))
    send_data html, type: "text/html; charset=utf-8", disposition: "inline"
  end

  # GET /lib/:file: the two libraries a generator may import.
  def lib
    name = params[:file]
    return head :not_found unless Validation::Harness::LIBS.include?(name)

    send_data Validation::Harness.file(name), type: Validation::Harness.content_type(name), disposition: "inline"
  end

  private

  def harden_headers
    response.set_header("Cache-Control", "no-store")
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("Referrer-Policy", "no-referrer")
  end
end
