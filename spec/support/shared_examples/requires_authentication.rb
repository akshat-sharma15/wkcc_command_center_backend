RSpec.shared_examples "requires api authentication" do
  it "returns 401 when no bearer token is given" do
    request_without_auth
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 when the bearer token is invalid" do
    request_with_invalid_auth
    expect(response).to have_http_status(:unauthorized)
  end
end
