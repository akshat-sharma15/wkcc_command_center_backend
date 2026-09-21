# Read-only access to Superset's users/roles, for alert recipient lookup.
# The one place that queries SupersetRole/SupersetUser/SupersetUserRole —
# controllers and AlertRule never touch those models directly. Every
# method degrades to an empty/nil result when Superset isn't configured
# (see SupersetRecord) rather than raising, since that's the expected
# state of this repository today.
class SupersetDirectory
  def self.configured?
    SupersetRecord.configured?
  end

  def self.roles
    return [] unless configured?

    SupersetRole.order(:name).map { |role| serialize_role(role) }
  end

  def self.users
    return [] unless configured?

    SupersetUser.order(:username).map { |user| serialize_user(user) }
  end

  def self.find_role(id)
    return nil unless configured? && id.present?

    role = SupersetRole.find_by(id: id)
    role && serialize_role(role)
  end

  def self.find_user(id)
    return nil unless configured? && id.present?

    user = SupersetUser.find_by(id: id)
    user && serialize_user(user)
  end

  def self.users_for_role(role_id)
    return [] unless configured? && role_id.present?

    user_ids = SupersetUserRole.where(role_id: role_id).pluck(:user_id)
    SupersetUser.where(id: user_ids).map { |user| serialize_user(user) }
  end

  def self.serialize_role(role)
    { id: role.id, name: role.name }
  end
  private_class_method :serialize_role

  def self.serialize_user(user)
    {
      id: user.id,
      name: [ user.first_name, user.last_name ].compact_blank.join(" ").presence || user.username,
      username: user.username,
      email: user.email
    }
  end
  private_class_method :serialize_user
end
