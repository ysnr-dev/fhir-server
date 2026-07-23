# FHIR_PROFILE_VALIDATION を典型的な入力ミス(空文字・大文字・タイプミス等)のまま
# 静かに無視するのではなく、起動時エラーにする。既定は Fhir::Profile.mode 側の
# "warn"(未設定時)なので、ここで落ちるのは値を明示指定した場合のみ。
VALID_FHIR_PROFILE_VALIDATION_MODES = %w[off warn enforce].freeze

if ENV.key?("FHIR_PROFILE_VALIDATION") && VALID_FHIR_PROFILE_VALIDATION_MODES.exclude?(ENV["FHIR_PROFILE_VALIDATION"])
  raise <<~MSG
    FHIR_PROFILE_VALIDATION=#{ENV['FHIR_PROFILE_VALIDATION'].inspect} is not a valid mode.
    Set it to one of: #{VALID_FHIR_PROFILE_VALIDATION_MODES.join(', ')} (or unset it for the default "warn").
  MSG
end
