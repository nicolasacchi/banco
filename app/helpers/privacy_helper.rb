# The privacy notice and the account page (D-357): their texts are structured locale entries (config/locales/privacy.*.yml), each
# section a hash with a title and any of paragraphs, items, steps. The operator's values and the portal's numbers fill the %{...}.
module PrivacyHelper
  PRIVACY_SECTIONS = %i[controller purposes basis data not_done who where retention append_only rights cookies].freeze
  ACCOUNT_SECTIONS = %i[how login session lockout reset logout care].freeze

  # A section of the notice: { title:, paragraphs: [...], items: [...], steps: [...] } with every string filled from values.
  def info_section(scope, key, values)
    deep_fill(I18n.t("#{scope}.#{key}"), values)
  end

  def info_text(key, values = {}) = deep_fill(I18n.t(key), values)

  private

  def deep_fill(node, values)
    case node
    when String then I18n.interpolate(node, values)
    when Array then node.map { |item| deep_fill(item, values) }
    when Hash then node.transform_values { |item| deep_fill(item, values) }
    else node
    end
  end
end
