require 'rails_helper'

RSpec.describe StorageUsageSync do
  let!(:with_files) { create(:storage_quota, used_bytes: 0) }
  let!(:without_files) { create(:storage_quota, used_bytes: 999) }

  it 'copies per-user usage from file-service and zeroes users without files' do
    allow(described_class).to receive(:fetch_usage)
      .and_return([{ 'owner_id' => with_files.user_id, 'used_bytes' => 4096 },
                   { 'owner_id' => SecureRandom.uuid, 'used_bytes' => 10 }])

    expect(described_class.call).to be(true)
    expect(with_files.reload.used_bytes).to eq(4096)
    expect(without_files.reload.used_bytes).to eq(0)
  end

  it 'zeroes everyone when file-service reports no files' do
    allow(described_class).to receive(:fetch_usage).and_return([])

    described_class.call
    expect(without_files.reload.used_bytes).to eq(0)
  end

  it 'keeps existing values when file-service is unreachable' do
    allow(described_class).to receive(:fetch_usage).and_raise(Errno::ECONNREFUSED)

    expect(described_class.call).to be(false)
    expect(without_files.reload.used_bytes).to eq(999)
  end

  it 'ignores rows with malformed owner ids' do
    allow(described_class).to receive(:fetch_usage)
      .and_return([{ 'owner_id' => "x'; DROP TABLE storage_quotas; --", 'used_bytes' => 1 }])

    expect(described_class.call).to be(true)
    expect(StorageQuota.count).to eq(2)
  end
end
