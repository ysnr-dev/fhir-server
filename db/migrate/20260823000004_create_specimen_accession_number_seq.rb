class CreateSpecimenAccessionNumberSeq < ActiveRecord::Migration[7.0]
  # Specimen.accessionIdentifier のサーバー採番(Fhir::AccessionAssigner)が使う連番。
  # schema.rb はシーケンスをダンプしないため、スキーマロードで作った DB には
  # 存在しないが、その場合は AccessionAssigner が初回利用時に作る。
  def up
    execute "CREATE SEQUENCE IF NOT EXISTS specimen_accession_number_seq"
  end

  def down
    execute "DROP SEQUENCE IF EXISTS specimen_accession_number_seq"
  end
end
