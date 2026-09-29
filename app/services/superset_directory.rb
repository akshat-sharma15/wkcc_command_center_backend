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

  # A user or role by logical reference ({ id:, name: }), or nil.
  # Memoized for PRINCIPAL_CACHE_TTL: incident cards render three
  # principals each, and a notification list renders many cards.
  PRINCIPAL_CACHE_TTL = 60.seconds

  def self.resolve_principal(type, id)
    key = [ type.to_s, id.to_i ]
    cached = principal_cache[key]
    return cached[:value] if cached && cached[:at] > PRINCIPAL_CACHE_TTL.ago

    value = case type.to_s
    when "user" then find_user(id)
    when "role" then find_role(id)
    end
    principal_cache[key] = { value: value, at: Time.current }
    value
  end

  def self.principal_cache
    @principal_cache ||= Concurrent::Map.new
  end
  private_class_method :principal_cache

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
