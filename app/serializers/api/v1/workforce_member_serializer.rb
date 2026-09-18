module Api
  module V1
    class WorkforceMemberSerializer
      def initialize(workforce_member)
        @workforce_member = workforce_member
      end

      def as_json(*)
        {
          id: @workforce_member.id,
          identifier: @workforce_member.identifier,
          name: @workforce_member.name,
          role_type: @workforce_member.role_type,
          hub_id: @workforce_member.hub_id,
          shift: @workforce_member.shift,
          attendance_status: @workforce_member.attendance_status,
          created_at: @workforce_member.created_at,
          updated_at: @workforce_member.updated_at
        }
      end
    end
  end
end
