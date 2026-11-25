require 'rails_helper'

RSpec.describe Api::V1::Admin::MetricsController do
  before { set_jwt_env(request) }

  describe 'GET #summary' do
    before do
      create_list(:admin_user, 2)
      create(:feature_flag, :enabled)
      create(:storage_quota)
    end

    it 'returns metrics summary' do
      get :summary
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key('users')
      expect(body).to have_key('storage')
      expect(body).to have_key('features')
      expect(body).to have_key('announcements')
      expect(body).to have_key('audit')
      expect(body).to have_key('documents')
      expect(body['users']['total']).to eq(2)
      expect(body['features']['enabled']).to eq(1)
    end

    context 'with auth-service users and documents' do
      let(:conn) { ActiveRecord::Base.connection }

      before do
        conn.execute(<<~SQL)
          CREATE TABLE users (
            id uuid PRIMARY KEY, email varchar NOT NULL, display_name varchar NOT NULL,
            avatar_url varchar, last_login_at timestamptz, created_at timestamptz NOT NULL DEFAULT NOW()
          );
          INSERT INTO users (id, email, display_name) VALUES (gen_random_uuid(), 'new@example.com', 'New User');
          CREATE TABLE documents (id uuid PRIMARY KEY, is_deleted boolean NOT NULL, is_template boolean NOT NULL);
          INSERT INTO documents VALUES (gen_random_uuid(), false, false), (gen_random_uuid(), false, false),
                                       (gen_random_uuid(), false, true), (gen_random_uuid(), true, false);
        SQL
      end

      it 'includes synced users and document counts for admins' do
        get :summary
        body = JSON.parse(response.body)
        expect(body['users']['total']).to eq(3)
        expect(body['documents']).to eq('total' => 2, 'templates' => 1)
      end

      it 'does not sync the directory for non-admins' do
        set_jwt_env(request, role: 'viewer')
        get :summary
        expect(JSON.parse(response.body)['users']['total']).to eq(2)
      end
    end
  end
end
