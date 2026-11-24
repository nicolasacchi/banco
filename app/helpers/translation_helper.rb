module TranslationHelper
  # The Italian translation of the english and spanish courses (D-402) on the course pages: topic titles, intros and skill names with their
  # authored Italian one tap away. The state machine is items/translation.js with translation.css: a node `.tr[lang=it][data-nospeech]` shows
  # when the scope around it is open (a list page is a scope of its own, `page`), or always for the preference «Sempre visibile» and for the teacher.

  # The title of a topic as the student reads it: `title_en|es` when the course entry has the pair, else the Italian (no translation to offer).
  # A plain string, for headings, page titles and sentences that interpolate it.
  def topic_title(topic) = topic.title

  # The same title for markup: the target-language text, and under it its Italian translation (hidden until the page opens it). An entry
  # without the pair is its Italian title, as before.
  def topic_title_html(topic)
    return topic.title unless topic.title_paired?

    safe_join([ tag.span(topic.title_target, lang: topic.lang), tr_node(topic.title_it) ])
  end

  # A translation node: <span class="tr" lang="it" data-nospeech>.
  def tr_node(text, tag: :span)
    content_tag(tag, text, class: "tr", lang: "it", data: { nospeech: "" })
  end

  # The attributes that make an element the scope of a list or topic page: closed (the preference opens it), the context of the event it
  # reports and the student's own address to post it to; the preview and the teacher have no address, so nothing is written.
  # Nothing at all when the page has no translation to offer (`offered` false): no scope, no button.
  def tr_scope_attrs(offered, topic: nil)
    return "" unless offered

    tag.attributes(data: { tr_scope: "page", translation: "off", tr_surface: "topics", tr_topic: topic&.key, tr_url: (spath("/translations") unless preview?) }.compact)
  end

  # The scope's «Traduzione» button (nothing when the page has no translation to offer): the page's own `data-controller="translation"` flips it.
  def tr_page_button(offered)
    return unless offered

    tag.button(tag.span(t("translation.toggle")), type: "button", class: "tr-toggle", "aria-pressed": "false",
                                                   data: { controller: "translation", action: "click->translation#toggle" })
  end

  # The page header's actions block with the button, or no block at all (no empty actions box) when there is nothing to offer.
  def tr_actions(offered) = (proc { tr_page_button(true) } if offered)

  # Whether any of these topics has a translation of its title to offer.
  def tr_titles?(topics) = Array(topics).any? { |topic| topic.title_paired? }
end
