# The deployed version string shown in the footer.
#
# In production the build script (bin/render-build.sh) stamps a `REVISION` file
# at the repo root with `git describe --tags --always` — a clean tag like
# "v0.1.0" when deployed from a release tag (the only thing we deploy), or a
# short SHA as a fallback. At runtime we just read that file; we never shell out
# to git on a production box (git history isn't guaranteed to be there).
#
# In development there's no REVISION file, so we fall back to a live
# `git describe` for convenience. Memoised: computed once per process.
module AppVersion
  REPO_URL = "https://github.com/knorrli/uesgu".freeze

  module_function

  def current
    @current ||= revision_file || git_describe || "dev"
  end

  # The best GitHub link for whatever `current` resolved to: the release page for
  # a clean tag, the commit for a bare SHA, else the repo's commit history.
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
