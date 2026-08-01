# Device has no mandatory elements in either base FHIR R4 or JP_Device (whose
# differential only marks meta.lastUpdated must-support), so this validator
# checks value formats and the one required binding rather than requiredness.
class DeviceValidator < ResourceValidator
  private

  def validate
    validate_binding("status", Fhir::Terminology::DEVICE_STATUS)
    validate_datetime("manufactureDate")
    validate_datetime("expirationDate")
    # Device.patient is 0..1 and targets Patient only, so anything else is a
    # value error rather than another permitted target type.
    validate_patient_reference("patient", on_non_patient: :reject)
  end
end
