class Invitation < ApplicationRecord
  Unavailable = Class.new(StandardError)

  CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".freeze
  CODE_LENGTH = 8

  belongs_to :created_by, class_name: "User"
  belongs_to :redeemed_by, class_name: "User", optional: true

  validates :code, presence: true, uniqueness: true

  before_validation :assign_code, on: :create

  scope :available, -> {
    where(redeemed_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current)
  }
  scope :redeemed, -> { where.not(redeemed_at: nil) }
  scope :expired, -> { where(redeemed_at: nil).where("expires_at <= ?", Time.current) }

  def self.normalize_code(raw)
    raw.to_s.gsub(/[^A-Za-z0-9]/, "").upcase
  end

  def self.available_by_code(raw)
    code = normalize_code(raw)
    return nil if code.blank?

    available.find_by(code: code)
  end

  def redeemed?
    redeemed_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def available?
    !redeemed? && !expired?
  end

  def status
    return :redeemed if redeemed?
    return :expired if expired?

    :available
  end

  def redeem!(user)
    with_lock do
      raise Unavailable unless available?

      update!(redeemed_by: user, redeemed_at: Time.current)
    end
  end

  def formatted_code
    code.scan(/.{1,4}/).join("-")
  end

  private

  def assign_code
    self.code ||= loop do
      candidate = Array.new(CODE_LENGTH) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.size)] }.join
      break candidate unless Invitation.exists?(code: candidate)
    end
  end
end
