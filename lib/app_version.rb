module AppVersion
  REPO_URL = "https://github.com/knorrli/uesgu".freeze

  module_function

  def current
    @current ||= revision_file || git_describe || "dev"
  end

  def url
    if release_tag?
      "#{REPO_URL}/releases/tag/#{current}"
    elsif current.match?(/\A[0-9a-f]{7,40}\z/)
      "#{REPO_URL}/commit/#{current}"
    else
      "#{REPO_URL}/commits"
    end
  end

  def release_tag?
    current.match?(/\Av\d+\.\d+\.\d+\z/)
  end

  def revision_file
    file = Rails.root.join("REVISION")
    file.exist? ? file.read.strip.presence : nil
  end

  def git_describe
    out = `git describe --tags --always 2>/dev/null`.strip
    out.presence
  rescue StandardError
    nil
  end
end
