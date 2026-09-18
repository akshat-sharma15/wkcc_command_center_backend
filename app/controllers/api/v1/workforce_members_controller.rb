module Api
  module V1
    class WorkforceMembersController < BaseController
      before_action :set_workforce_member, only: %i[show update destroy]

      def index
        pagy, members = pagy(WorkforceMember.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: members.map { |m| WorkforceMemberSerializer.new(m).as_json }
      end

      def show
        render json: WorkforceMemberSerializer.new(@workforce_member).as_json
      end

      def create
        member = WorkforceMember.new(workforce_member_params)
        member.save!
        render json: WorkforceMemberSerializer.new(member).as_json, status: :created
      end

      def update
        @workforce_member.update!(workforce_member_params)
        render json: WorkforceMemberSerializer.new(@workforce_member).as_json
      end

      def destroy
        @workforce_member.destroy!
        head :no_content
      end

      private

      def set_workforce_member
        @workforce_member = WorkforceMember.find(params[:id])
      end

      def workforce_member_params
        params.require(:workforce_member).permit(:identifier, :name, :role_type, :hub_id, :shift, :attendance_status)
      end
    end
  end
end
