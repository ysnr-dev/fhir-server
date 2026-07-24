# A patient-facing account for the interactive SMART launch. Bound 1:1 to a
# FHIR Patient, which becomes the launch context of every token issued for this
# user -- so consent never involves choosing a patient.
#
# Deliberately minimal: no self-service registration, no password reset, no
# roles. Accounts are provisioned out of band (rake fhir:register_user).
class User < ApplicationRecord
  has_secure_password

  belongs_to :patient

  has_many :authorization_codes, dependent: :destroy
  has_many :access_tokens, dependent: :nullify

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :patient_id, presence: true, uniqueness: true

  # Rails' authenticate_by does the digest comparison in constant time and
  # burns an equivalent amount of work when the email is unknown, so a missing
  # account is not distinguishable by timing from a wrong password.
  def self.authenticate(email:, password:)
    return nil if email.blank? || password.blank?

    authenticate_by(email: email.to_s.strip.downcase, password: password)
  end

  def display_name
    name.presence || email
  end
end
