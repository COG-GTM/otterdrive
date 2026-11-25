module Api
  module V1
    module Admin
      class MetricsController < ApplicationController
        # GET /api/v1/admin/metrics/summary
        def summary
          if ADMIN_ROLES.include?(current_user_role)
            UserDirectorySync.call
            StorageUsageSync.call
          end
          render json: MetricsAggregator.summary
        end
      end
    end
  end
end
