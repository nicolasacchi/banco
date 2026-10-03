module Validation
  # What the blueprint checks need to know about a pinned item revision, read from
  # its rows: the skills it measures, whether its latest validation passed, and its
  # instances (fingerprint and whether the instance is hard to guess).
  module ItemInfo
    module_function

    def for(revision)
      body = JSON.parse(revision.body_json)
      kind = body["kind"] || "diagnosis_item"
      component = body["component"] || "number"
      skills = kind == "testlet" ? Array(body["sub_items"]).map { |s| s["skill"] } : [ body["skill"] ]
      BlueprintChecks::ItemInfo.new(
        id: revision.id, skills: skills, passed: revision.status == "passed",
        instances: revision.instances.order(:id).map do |inst|
          { fingerprint: inst.fingerprint, low_guess: Diagnosis::Rules::V1.low_guess?(component, size: size_of(JSON.parse(inst.display_json), component)) }
        end
      )
    end

    # The lookup BlueprintChecks wants: id string => info or nil.
    def lookup = ->(id) { (rev = ItemRevision.find_by(id: id)) && self.for(rev) }

    # Elements of an ordering or pairs of a matching, to decide whether it is hard to guess.
    def size_of(display, component)
      case component
      when "ordering" then Array(display["elements"]).size
      when "matching" then Array(display["left"]).size
      end
    end
  end
end
