class AddCanonicalUniqueIndexToQuestionnaires < ActiveRecord::Migration[7.0]
  # (url, version) はテンプレートの canonical。重複すると QuestionnaireResponse.questionnaire
  # がどのテンプレートを指すか判別できないため、DB 層で一意を保証する。
  # - url は任意項目のため url IS NOT NULL の partial index
  # - 論理削除後の再作成・履歴行は許容するため deleted = false に限定
  # - version NULL 同士の重複も防ぐため COALESCE の式 index(PG15 の NULLS NOT DISTINCT 非依存)
  def up
    duplicates = select_all(<<~SQL.squish)
      SELECT url, version, COUNT(*) AS cnt FROM questionnaires
      WHERE deleted = false AND url IS NOT NULL
      GROUP BY url, version HAVING COUNT(*) > 1
    SQL

    if duplicates.any?
      details = duplicates.map { |row| "#{row['url']}|#{row['version']} (#{row['cnt']}件)" }.join(", ")
      raise <<~MSG
        canonical が重複した Questionnaire が存在するため一意 index を作成できません: #{details}
        重複を手動で整理(削除または version 変更)してから再度 migrate してください。
      MSG
    end

    add_index :questionnaires, "url, COALESCE(version, '')",
              unique: true,
              where: "deleted = false AND url IS NOT NULL",
              name: "index_questionnaires_on_canonical_unique"
  end

  def down
    remove_index :questionnaires, name: "index_questionnaires_on_canonical_unique"
  end
end
