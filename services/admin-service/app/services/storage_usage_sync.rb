require 'net/http'

# Copies per-user stored bytes from file-service (which owns file metadata)
# into storage_quotas.used_bytes so the dashboard reports real usage.
class StorageUsageSync
  TIMEOUT_SECONDS = 3
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  def self.call
    usage = fetch_usage
    return false unless usage

    conn = ActiveRecord::Base.connection
    rows = usage.filter_map do |row|
      id = row['owner_id'].to_s
      "(#{conn.quote(id)}::uuid, #{Integer(row['used_bytes'])})" if id.match?(UUID_FORMAT)
    end
    source = rows.any? ? "VALUES #{rows.join(', ')}" : 'SELECT NULL::uuid, NULL::bigint WHERE FALSE'

    # Users file-service doesn't list have no files, so they drop to zero.
    conn.exec_update(<<~SQL.squish)
      UPDATE storage_quotas q
      SET used_bytes = COALESCE(v.used, 0), updated_at = NOW()
      FROM storage_quotas q2
      LEFT JOIN (#{source}) v(user_id, used) ON v.user_id = q2.user_id
      WHERE q.id = q2.id AND q.used_bytes IS DISTINCT FROM COALESCE(v.used, 0)
    SQL
    true
  rescue StandardError => e
    Rails.logger.warn("storage_usage_sync_failed: #{e.class}: #{e.message}")
    false
  end

  def self.fetch_usage
    uri = URI.join(ENV.fetch('FILE_SERVICE_URL', 'http://file-service:8082'), '/internal/storage-usage')
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                              open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
      http.get(uri.request_uri)
    end
    return nil unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body).fetch('users')
  end
end
