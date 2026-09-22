FactoryBot.define do
  factory :notification do
    alert
    recipient_user_id { 1 }
    channel { "in_app" }
    status { "pending" }
    title { "Test Notification" }
    message { "Something happened." }
  end
end
