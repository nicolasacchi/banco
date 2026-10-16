# The shared components of the interface (D-306, docs/ui.md): small helpers where a component is more than one class.
# The CSS is app/assets/stylesheets/components.css on the tokens of application.css. Icons come from the Lucide sprite
# (config/banco/icons.yml, bin/build-icons); a new icon is a change of that file.
module UiHelper
  SPRITE = "/vendor/lucide@1.54.0/banco-sprite.svg".freeze
  # The tones of a notice or a pill and the icon each starts with. Never red and green for right and wrong.
  NOTICE_ICONS = { info: "info", success: "circle-check", nearly: "triangle-alert", error: "alert", hint: "wrong-hint" }.freeze

  # A decorative icon of the sprite: the words next to it carry the meaning, so it is hidden from a screen reader.
  def ui_icon(name, css: nil)
    tag.svg(tag.use(nil, href: "#{SPRITE}##{name}"), class: [ "ic", css ].compact.join(" "), "aria-hidden": "true", focusable: "false")
  end

  # <div class="notice KIND"> icon + body. Errors are announced at once (role alert), the rest politely (role status).
  def ui_notice(kind = :info, text = nil, title: nil, html: {}, &block)
    kind = kind.to_sym
    raise ArgumentError, "unknown notice #{kind}" unless NOTICE_ICONS.key?(kind)
    body = block ? capture(&block) : text
    inner = safe_join([ (tag.span(title, class: "notice-title") if title), body ].compact)
    css = [ "notice", kind, html[:class] ].compact.join(" ")
    tag.div(ui_icon(NOTICE_ICONS[kind]) + tag.div(inner, class: "notice-body"), **html.except(:class), class: css, role: kind == :error ? "alert" : "status")
  end

  # A state pill: the word first, an optional icon, the tone from the modifier (info, success, nearly, error, hint, muted).
  def ui_pill(text, tone = :muted, icon: nil)
    tag.span(safe_join([ (ui_icon(icon) if icon), text ].compact), class: "pill #{tone}")
  end

  # A quiet label or a count.
  def ui_tag(text, icon: nil) = tag.span(safe_join([ (ui_icon(icon) if icon), text ].compact), class: "tag")

  # The header of a page: an optional back link (one way back, never two), the title, actions, a line under them.
  #   <%= ui_page_header "Titolo", back: ["Materie", "/subjects"], sub: "..." do %> buttons <% end %>
  def ui_page_header(title, back: nil, sub: nil, &block)
    back_link = back && link_to(safe_join([ ui_icon("back"), back.first ]), back.last, class: "back")
    actions = block ? tag.div(capture(&block), class: "page-actions") : nil
    tag.header(safe_join([ back_link, tag.h1(title), actions, (tag.p(sub, class: "page-sub") if sub) ].compact), class: "page-header")
  end

  # A table that scrolls inside its own box. The wrapper takes focus so a keyboard can scroll it.
  def ui_table_wrap(label: nil, &block)
    tag.div(capture(&block), class: "table-wrap", tabindex: 0, role: "region", "aria-label": label)
  end

  # An empty state: icon, one sentence, one next action (a link or nothing).
  def ui_empty(text, action: nil, icon: "empty")
    tag.div(safe_join([ ui_icon(icon), tag.p(text), (link_to(action.first, action.last, class: "button secondary") if action) ].compact), class: "empty")
  end

  # A loading state; the sentence is announced politely.
  def ui_loading(text) = tag.p(safe_join([ ui_icon("loading"), text ]), class: "loading", role: "status")

  # An integer 0..100 for .meter: <span class="meter"><span style="width:40%">.
  def ui_meter(percent, label)
    value = percent.to_i.clamp(0, 100)
    tag.span(tag.span(nil, style: "width: #{value}%"), class: "meter", role: "progressbar", "aria-valuenow": value, "aria-valuemin": 0, "aria-valuemax": 100, "aria-label": label)
  end

  # A date or time for people ("2 nov 2026, 09:00"), Italian, in Rome time. Nil or unparsable text come back as given.
  MONTHS_IT = %w[gen feb mar apr mag giu lug ago set ott nov dic].freeze
  def ui_time(value, time: true)
    t = (value.respond_to?(:in_time_zone) ? value : (Time.zone.parse(value.to_s) if value.present?))&.in_time_zone("Europe/Rome")
    return value.to_s if t.nil?
    day = "#{t.day} #{MONTHS_IT[t.month - 1]} #{t.year}"
    time ? "#{day}, #{t.strftime('%H:%M')}" : day
  rescue ArgumentError
    value.to_s
  end
end
