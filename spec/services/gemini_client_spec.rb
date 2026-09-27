require "rails_helper"

RSpec.describe GeminiClient do
  let(:endpoint) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent" }

  describe ".configured?" do
    it "is true only when GEMINI_API_KEY is present" do
      expect(described_class.configured?).to eq(ENV["GEMINI_API_KEY"].present?)
    end
  end

  describe "#initialize" do
    it "raises ConfigurationError when no api key is available" do
      expect { described_class.new(api_key: nil) }.to raise_error(described_class::ConfigurationError)
    end
  end

  describe "#generate" do
    let(:client) { described_class.new(api_key: "test-key", model: "gemini-3.8-flash") }
    let(:contents) { [ { role: "user", parts: [ { text: "hello" } ] } ] }

    before { allow(client).to receive(:sleep) }

    it "POSTs to the classic generateContent endpoint with contents, tools, and systemInstruction, authenticated via x-goog-api-key" do
      stub = stub_request(:post, endpoint)
        .with(
          headers: { "x-goog-api-key" => "test-key", "Content-Type" => "application/json" },
          body: hash_including(
            "contents" => [ { "role" => "user", "parts" => [ { "text" => "hello" } ] } ],
            "tools" => [ { "functionDeclarations" => [ { "name" => "x" } ] } ],
            "systemInstruction" => { "parts" => [ { "text" => "be nice" } ] }
          )
        )
        .to_return(status: 200, body: { candidates: [ { content: { parts: [ { text: "hi there" } ], role: "model" } } ] }.to_json,
          headers: { "Content-Type" => "application/json" })

      result = client.generate(contents: contents, tools: [ { name: "x" } ], system_instruction: "be nice")

      expect(stub).to have_been_requested
      expect(result.dig("candidates", 0, "content", "parts", 0, "text")).to eq("hi there")
    end

    it "omits tools/systemInstruction when not given" do
      stub_request(:post, endpoint)
        .with { |req| body = JSON.parse(req.body); !body.key?("tools") && !body.key?("systemInstruction") }
        .to_return(status: 200, body: { candidates: [] }.to_json)

      client.generate(contents: contents)
    end

    it "raises ApiError surfacing Gemini's own message (without leaking the API key) once retries are exhausted" do
      stub_request(:post, endpoint)
        .to_return(status: 503, body: { error: { message: "This model is currently experiencing high demand." } }.to_json)

      expect { client.generate(contents: contents) }.to raise_error(described_class::ApiError) do |error|
        expect(error.message).to include("high demand")
        expect(error.message).not_to include("test-key")
      end
    end

    it "raises ApiError immediately on a non-retryable error response (e.g. bad request), without retrying" do
      stub = stub_request(:post, endpoint)
        .to_return(status: 400, body: { error: { message: "Invalid argument" } }.to_json)

      expect { client.generate(contents: contents) }.to raise_error(described_class::ApiError, /Invalid argument/)
      expect(stub).to have_been_requested.times(1)
    end

    it "retries on a transient 503 and succeeds once Gemini recovers" do
      stub_request(:post, endpoint)
        .to_return(status: 503, body: { error: { message: "high demand" } }.to_json)
        .then
        .to_return(status: 200, body: { candidates: [ { content: { parts: [ { text: "hi there" } ], role: "model" } } ] }.to_json)

      result = client.generate(contents: contents)

      expect(result.dig("candidates", 0, "content", "parts", 0, "text")).to eq("hi there")
      expect(client).to have_received(:sleep).once
    end

    it "retries on 429 (quota exceeded) up to the max attempt count, then gives up" do
      stub = stub_request(:post, endpoint)
        .to_return(status: 429, body: { error: { message: "Quota exceeded" } }.to_json)

      expect { client.generate(contents: contents) }.to raise_error(described_class::ApiError, /Quota exceeded/)
      expect(stub).to have_been_requested.times(described_class::MAX_ATTEMPTS)
      expect(client).to have_received(:sleep).twice
    end

    it "raises ApiError on a network failure" do
      stub_request(:post, endpoint).to_timeout

      expect { client.generate(contents: contents) }.to raise_error(described_class::ApiError)
    end

    it "raises ApiError on an unparseable response body" do
      stub_request(:post, endpoint).to_return(status: 200, body: "not json")

      expect { client.generate(contents: contents) }.to raise_error(described_class::ApiError)
    end
  end
end
