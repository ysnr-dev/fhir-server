# QuestionnaireResponse を記入者名(author-name)で検索できるようにする。抽出列は書き込み時に
# しか埋まらないので、既存の回答はここで content から起こす(本番には Shell が無い)。
class AddAuthorNameKeyToQuestionnaireResponses < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real model.
  class MigrationQuestionnaireResponse < ActiveRecord::Base
    self.table_name = "questionnaire_responses"
  end

  def up
    add_column :questionnaire_responses, :author_name_key, :string
    add_index :questionnaire_responses, :author_name_key

    MigrationQuestionnaireResponse.reset_column_information
    backfill
  end

  def down
    remove_index :questionnaire_responses, :author_name_key
    remove_column :questionnaire_responses, :author_name_key
  end

  private

  # 無料枠は RAM 512MB なので、小さめのバッチで回す。
  def backfill
    MigrationQuestionnaireResponse
      .where("content ? 'contained'")
      .find_each(batch_size: 200) do |response|
        response.update_columns(author_name_key: name_key(response.content["contained"]))
      end
  end

  # Fhir::FieldExtractor.contained_practitioner_name_key と同じ規則。
  def name_key(contained)
    practitioner = Array.wrap(contained).find { |r| r.is_a?(Hash) && r["resourceType"] == "Practitioner" }
    name = Array.wrap(practitioner && practitioner["name"]).first
    text = name.is_a?(Hash) ? name["text"] : nil
    text.to_s.gsub(/[[:space:]]/, "").presence
  end
end
