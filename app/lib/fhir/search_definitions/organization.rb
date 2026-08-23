module Fhir
  module SearchDefinitions
    module Organization
      PARAMS = {
        # column は _sort=identifier のためだけにある(識別子の一致検索は
        # resource_identifiers を引く。Fhir::Search#identifier_fragment 参照)。
        "identifier" => { type: :identifier, column: :identifier_value },
        "name"       => { type: :string, column: :name },
        "active"     => { type: :boolean, column: :active },
        # Organization.type。診療科(dept)と施設(prov)を分けるのに使う
        # (これまでは partof:missing で代用していた)。
        "type"       => { type: :token },
        "partof"     => { type: :reference, column: :partof_reference, target_type: "Organization" }
      }.freeze
    end
  end
end
