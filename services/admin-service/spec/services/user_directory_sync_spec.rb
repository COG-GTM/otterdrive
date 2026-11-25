require 'rails_helper'

RSpec.describe UserDirectorySync do
  let(:conn) { ActiveRecord::Base.connection }

  def create_auth_tables
    conn.execute(<<~SQL)
      CREATE TABLE users (
        id uuid PRIMARY KEY, email varchar NOT NULL, display_name varchar NOT NULL,
        avatar_url varchar, last_login_at timestamptz, created_at timestamptz NOT NULL DEFAULT NOW()
      );
      CREATE TABLE user_roles (user_id uuid NOT NULL, role varchar NOT NULL);
    SQL
  end

  def insert_auth_user(email:, roles: ['USER'])
    id = SecureRandom.uuid
    conn.execute("INSERT INTO users (id, email, display_name) VALUES ('#{id}', '#{email}', 'Test User')")
    roles.each { |r| conn.execute("INSERT INTO user_roles VALUES ('#{id}', '#{r}')") }
    id
  end

  it 'is a no-op when the auth-service users table is absent' do
    expect(described_class.call).to eq(0)
    expect(AdminUser.count).to eq(0)
  end

  context 'with auth-service tables' do
    before { create_auth_tables }

    it 'mirrors registered users with a default quota and maps auth roles' do
      user_id = insert_auth_user(email: 'user@example.com')
      admin_id = insert_auth_user(email: 'boss@example.com', roles: %w[ADMIN USER])
      owner_id = insert_auth_user(email: 'owner@example.com', roles: %w[OWNER ADMIN])
      editor_id = insert_auth_user(email: 'editor@example.com', roles: %w[EDITOR USER])

      expect(described_class.call).to eq(4)

      expect(AdminUser.find(user_id)).to have_attributes(email: 'user@example.com', role: 'viewer', status: 'active')
      expect(AdminUser.find(admin_id).role).to eq('admin')
      expect(AdminUser.find(owner_id).role).to eq('super_admin')
      expect(AdminUser.find(editor_id).role).to eq('editor')
      expect(StorageQuota.find_by(user_id: user_id)).to have_attributes(tier: 'free', used_bytes: 0)
    end

    it 'is idempotent and keeps admin-managed fields of existing records' do
      existing = create(:admin_user, email: 'user@example.com', role: 'editor')
      insert_auth_user(email: 'user@example.com')

      2.times { described_class.call }

      expect(AdminUser.count).to eq(1)
      expect(existing.reload.role).to eq('editor')
    end

    it 'imports accounts whose email differs only by case' do
      create(:admin_user, email: 'User@Example.com')
      insert_auth_user(email: 'user@example.com')

      expect(described_class.call).to eq(1)
      expect(AdminUser.count).to eq(2)
    end

    it 'refreshes profile and login data on later syncs but keeps role and status' do
      id = insert_auth_user(email: 'user@example.com')
      described_class.call
      AdminUser.find(id).update!(role: 'editor', status: 'suspended')

      conn.execute("UPDATE users SET display_name = 'Renamed', last_login_at = NOW() WHERE id = '#{id}'")
      described_class.call

      expect(AdminUser.find(id)).to have_attributes(display_name: 'Renamed', role: 'editor', status: 'suspended')
      expect(AdminUser.find(id).last_login_at).to be_present
    end

    it 'keeps the last valid name when auth-service has a blank one' do
      id = insert_auth_user(email: 'user@example.com')
      described_class.call
      conn.execute("UPDATE users SET display_name = '  ' WHERE id = '#{id}'")
      described_class.call

      expect(AdminUser.find(id).display_name).to eq('Test User')
    end
  end
end
