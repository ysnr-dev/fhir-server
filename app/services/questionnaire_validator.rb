# Questionnaire against the JASPEHR IG v1.0.0 profile
# (http://www.hosp.ncgm.go.jp/JASPEHR/fhir/StructureDefinition/jaspehr-questionnaire).
#
# Cardinality, fixed values and slicing are covered by the vendored
# StructureDefinition (Fhir::Profile::Validator). What lives here is what that
# engine cannot do: the jsp-1..10 FHIRPath invariants, and the two required
# bindings whose ValueSets expand over an HL7 base CodeSystem this server does
# not vendor (so DefinitionStore reports "expansion unknown" and skips them).
class QuestionnaireValidator < ResourceValidator
  PROFILE_LABEL = "JASPEHR".freeze

  ITEM_CONTROL_EXTENSION = "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl".freeze
  MAX_OCCURS_EXTENSION = "http://hl7.org/fhir/StructureDefinition/questionnaire-maxOccurs".freeze
  INITIAL_EXPRESSION_EXTENSION =
    "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-initialExpression".freeze
  CALCULATED_EXPRESSION_EXTENSION =
    "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression".freeze

  private

  def validate
    require_field("version", cardinality: "1..1")
    validate_name
    require_field("title", cardinality: "1..1")
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::QUESTIONNAIRE_STATUS)
    require_field("subjectType", cardinality: "1..1")
    validate_datetime("date")
    validate_items
  end

  # jsp-5: charset plus a 15-character cap.
  def validate_name
    return unless require_field("name", cardinality: "1..1")

    name = payload["name"]
    unless name.is_a?(String) && name.match?(Fhir::Terminology::JASPEHR_TOKEN_PATTERN)
      return add_error(
        code: "value",
        diagnostics: "Questionnaire.name '#{name}' must match #{Fhir::Terminology::JASPEHR_TOKEN_PATTERN.source} (JASPEHR jsp-5)",
        expression: "Questionnaire.name"
      )
    end

    return if name.length <= Fhir::Terminology::JASPEHR_NAME_MAX_LENGTH

    add_error(
      code: "value",
      diagnostics: "Questionnaire.name must be at most #{Fhir::Terminology::JASPEHR_NAME_MAX_LENGTH} characters (JASPEHR jsp-5)",
      expression: "Questionnaire.name"
    )
  end

  def validate_items
    items = payload["item"]
    return unless require_field("item", cardinality: "1..*")

    unless items.is_a?(Array) && items.any?
      return add_error(
        code: "structure",
        diagnostics: "Questionnaire.item must be a non-empty array",
        expression: "Questionnaire.item"
      )
    end

    walk_items(items, "Questionnaire.item")
  end

  # Depth-first over the item tree. Each item is checked on its own (jsp-1, 3,
  # 4, 6, 7, 8, 10) and against its children (jsp-2, jsp-9) -- the parent-scoped
  # pair is written the way the IG expresses it, so a top-level item, having no
  # parent, is not constrained by them.
  def walk_items(items, base_expression)
    items.each_with_index do |item, index|
      next unless item.is_a?(Hash)

      expression = "#{base_expression}[#{index}]"
      validate_item(item, expression)
      validate_children(item, expression)

      children = item["item"]
      walk_items(children, "#{expression}.item") if children.is_a?(Array)
    end
  end

  def validate_item(item, expression)
    validate_link_id(item, expression)
    validate_item_type(item, expression)

    type = item["type"]

    # jsp-1 / jsp-3: enableWhen and repeats are group-only.
    if item.key?("enableWhen") && type != "group"
      add_invariant("jsp-1", "only 'group' items can have enableWhen", "#{expression}.enableWhen")
    end
    if item.key?("repeats") && type != "group"
      add_invariant("jsp-3", "only 'group' items can have repeats", "#{expression}.repeats")
    end

    # jsp-8: even a group cannot combine the two.
    if item.key?("enableWhen") && item.key?("repeats")
      add_invariant("jsp-8", "an item cannot have both enableWhen and repeats", "#{expression}")
    end

    # jsp-7: an item is driven either by an initial value or by a calculation.
    if extension?(item, INITIAL_EXPRESSION_EXTENSION) && extension?(item, CALCULATED_EXPRESSION_EXTENSION)
      add_invariant("jsp-7", "an item cannot have both initialExpression and calculatedExpression", "#{expression}.extension")
    end

    # jsp-6 / jsp-10: the two extensions the IG makes conditionally mandatory.
    if type == "choice" && !extension?(item, ITEM_CONTROL_EXTENSION)
      add_invariant("jsp-6", "an item of type 'choice' requires the questionnaire-itemControl extension", "#{expression}.extension")
    end
    if item["repeats"] == true && !extension?(item, MAX_OCCURS_EXTENSION)
      add_invariant("jsp-10", "a repeating item requires the questionnaire-maxOccurs extension", "#{expression}.extension")
    end
  end

  # jsp-2 / jsp-9: both describe how an item gates its own children.
  def validate_children(item, expression)
    children = item["item"]
    return unless children.is_a?(Array) && children.any?

    gated = children.select { |child| child.is_a?(Hash) && child.key?("enableWhen") }

    if item["type"] == "choice"
      if gated.size != children.size
        add_invariant("jsp-9", "every item under a 'choice' item must have enableWhen", "#{expression}.item")
      end
    elsif gated.any?
      add_invariant("jsp-9", "only items under a 'choice' item may have enableWhen", "#{expression}.item")
    end

    return if gated.empty?

    questions = gated.flat_map { |child| Array.wrap(child["enableWhen"]).filter_map { |w| w["question"] if w.is_a?(Hash) } }.uniq
    return if questions.all? { |question| question == item["linkId"] }

    add_invariant(
      "jsp-2",
      "enableWhen.question of a child item must be the parent item's linkId ('#{item['linkId']}')",
      "#{expression}.item"
    )
  end

  # jsp-4
  def validate_link_id(item, expression)
    link_id = item["linkId"]
    return unless require_field("item.linkId", value: link_id, expression: "#{expression}.linkId", cardinality: "1..1")
    return if link_id.is_a?(String) && link_id.match?(Fhir::Terminology::JASPEHR_TOKEN_PATTERN)

    add_invariant("jsp-4", "linkId '#{link_id}' must match #{Fhir::Terminology::JASPEHR_TOKEN_PATTERN.source}", "#{expression}.linkId")
  end

  def validate_item_type(item, expression)
    return unless require_field("item.type", value: item["type"], expression: "#{expression}.type", cardinality: "1..1")

    validate_binding(
      "item.type",
      Fhir::Terminology::QUESTIONNAIRE_ITEM_TYPE_JASPEHR,
      value: item["type"],
      expression: "#{expression}.type"
    )
  end

  def extension?(item, url)
    Array.wrap(item["extension"]).any? { |ext| ext.is_a?(Hash) && ext["url"] == url }
  end

  def add_invariant(key, message, expression)
    add_error(code: "invariant", diagnostics: "#{message} (JASPEHR #{key})", expression: expression)
  end
end
