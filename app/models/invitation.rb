class Invitation < ApplicationRecord
  # Single-use, admin-minted registration codes. The invite gate is üsgu's
  # anti-bot defence (no CAPTCHA, no forced email verification — see project
  # ethos), so a code must be unguessable AND consumable exactly once.
  #
  # Raised when a code is redeemed after it has already been spent or has
  # expired — including a race where two people submit the same code at once.
  Unavailable = Class.new(StandardError)

  # Crockford-ish alphabet: no 0/O/1/I/L so a code is safe to read aloud or
  # copy from a chat without ambiguity. 31^8 ≈ 8.5e11 combinations.
  CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".freeze
  CODE_LENGTH = 8

  belongs_to :created_by, class_name: "User"
  belongs_to :redeemed_by, class_name: "User", optional: true

  validates :code, presence: true, uniqueness: true

  before_validation :assign_code, on: :create

  # Usable right now: not yet redeemed and not past its (optional) expiry.
  scope :available, -> {
    where(redeemed_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current)
  }
  scope :redeemed, -> { where.not(redeemed_at: nil) }
  scope :expired, -> { where(redeemed_at: nil).where("expires_at <= ?", Time.current) }

  # Strip formatting/case so a friend can type "abcd-2345" or "ABCD 2345".
  def self.normalize_code(raw)
    raw.to_s.gsub(/[^A-Za-z0-9]/, "").upcase
  end

  # Look up an available invitation by a user-entered code, or nil.
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

  # Spend the code for `user`. Locks the row and re-checks availability inside
  # the transaction so a concurrent redemption of the same single-use code
  # loses the race and raises Unavailable rather than double-spending.
  def redeem!(user)
    with_lock do
      raise Unavailable unless available?

      update!(redeemed_by: user, redeemed_at: Time.current)
    end
  end

  # ABCD-2345 — for display only; never used for lookup.
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
