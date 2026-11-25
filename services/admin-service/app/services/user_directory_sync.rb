# Mirrors accounts registered through auth-service (the shared `users` table)
# into admin_users so the admin dashboard reflects real users, not only seeds.
class UserDirectorySync
  DEFAULT_TIER = 'free'.freeze

  def self.call
    conn = ActiveRecord::Base.connection
    return 0 unless conn.table_exists?('users')

    # Profile fields are owned by auth-service; role/status stay admin-managed.
    conn.exec_update(<<~SQL.squish)
      UPDATE admin_users a
      SET display_name = u.display_name, avatar_url = u.avatar_url,
          last_login_at = u.last_login_at, updated_at = NOW()
      FROM users u
      WHERE a.id = u.id
        AND (a.display_name, a.avatar_url, a.last_login_at)
            IS DISTINCT FROM (u.display_name, u.avatar_url, u.last_login_at)
    SQL

    inserted = conn.exec_update(<<~SQL.squish)
      INSERT INTO admin_users (id, email, display_name, role, status, avatar_url,
                               last_login_at, created_at, updated_at)
      SELECT u.id, u.email, u.display_name, #{role_sql(conn)}, 'active', u.avatar_url,
             u.last_login_at, u.created_at, NOW()
      FROM users u
      WHERE NOT EXISTS (
        SELECT 1 FROM admin_users a WHERE a.id = u.id OR a.email = u.email
      )
      ON CONFLICT DO NOTHING
    SQL

    conn.exec_update(<<~SQL.squish)
      INSERT INTO storage_quotas (id, user_id, quota_bytes, used_bytes, tier, created_at, updated_at)
      SELECT gen_random_uuid(), a.id, #{StorageQuota::TIER_LIMITS.fetch(DEFAULT_TIER)}, 0,
             '#{DEFAULT_TIER}', NOW(), NOW()
      FROM admin_users a
      JOIN users u ON u.id = a.id
      WHERE NOT EXISTS (SELECT 1 FROM storage_quotas q WHERE q.user_id = a.id)
      ON CONFLICT (user_id) DO NOTHING
    SQL

    inserted
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn("user_directory_sync_failed: #{e.message}")
    0
  end

  def self.role_sql(conn)
    return "'viewer'" unless conn.table_exists?('user_roles')

    has_role = ->(role) { "EXISTS (SELECT 1 FROM user_roles r WHERE r.user_id = u.id AND r.role = '#{role}')" }
    "CASE WHEN #{has_role.call('OWNER')} THEN 'super_admin' " \
      "WHEN #{has_role.call('ADMIN')} THEN 'admin' " \
      "WHEN #{has_role.call('EDITOR')} THEN 'editor' ELSE 'viewer' END"
  end

  private_class_method :role_sql
end
