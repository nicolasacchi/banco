# One way to show a skill key or an item key on the teacher's pages (D-218): the Italian name,
# the technical key small and grey after it, and an info button that opens a native popover
# with the card of the reference. Popovers go to the end of the page (content_for
# :ref_popovers), so they never sit inside a paragraph or a heading. No script is involved.
module RefsHelper
  # target: a skill key, an item key, an Item or an ItemRevision. href: makes the name a link
  # (a skill's graph anchor, the skill screen); with none the name is plain text.
  # popover: false drops the info button and the card (inside a label, where a button must not sit).
  # A key nothing knows is shown as the bare key, in the key style.
  def ref_for(target, href: nil, popover: true)
    card = teacher_refs.resolve(target)
    return content_tag(:span, target.respond_to?(:key) ? target.key : target.to_s, class: "key ref-unknown") unless card

    unless popover
      return tag.span(safe_join([ content_tag(:span, card.name, class: "ref-name"), " ", content_tag(:span, "(#{card.key})", class: "key") ]), class: "ref", "data-ref": card.kind, "data-ref-key": card.key)
    end

    id = "refpop-#{@_ref_seq = @_ref_seq.to_i + 1}"
    name = href ? link_to(card.name, href, class: "ref-name") : content_tag(:span, card.name, class: "ref-name")
    button = tag.button(t("teacher.refs.info_mark"), type: "button", class: "ref-info no-print", popovertarget: id, popovertargetaction: "toggle",
                        "aria-label": t("teacher.refs.info", name: card.name))
    content_for(:ref_popovers, ref_popover(id, card))
    tag.span(safe_join([ name, " ", content_tag(:span, "(#{card.key})", class: "key"), " ", button ]), class: "ref", "data-ref": card.kind, "data-ref-key": card.key)
  end

  # The name alone, as a link to the permalink page: for lists inside a card.
  def ref_link(key, label = nil)
    link_to(label || teacher_refs.skill_label(key), teacher_ref_path(key: key), class: "ref-link")
  end

  def component_name(component) = Teacher::Refs.component_name(component)

  def teacher_refs = @_teacher_refs ||= Teacher::Refs.new

  private

  # Rendered once per key and request: the card is the same for every occurrence, only the id differs.
  def ref_popover(id, card)
    @_ref_cards ||= {}
    body = @_ref_cards[[ card.kind, card.key ]] ||= render("teacher/refs/card", card: card, permalink: true)
    tag.div(safe_join([
      tag.div(safe_join([ tag.strong(card.name, id: "#{id}-title"),
                          tag.button(t("teacher.refs.close"), type: "button", class: "button secondary small", popovertarget: id, popovertargetaction: "hide") ]), class: "ref-card-head"),
      body
    ]), id: id, popover: "auto", class: "ref-card no-print", role: "dialog", "aria-labelledby": "#{id}-title")
  end
end
