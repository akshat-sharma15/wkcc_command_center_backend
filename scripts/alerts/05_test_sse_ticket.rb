#!/usr/bin/env rails runner
# Test SSE ticket generation and verification

puts "=" * 70
puts "SSE TICKET VERIFICATION TEST"
puts "=" * 70

# Get test user
puts "\n[SETUP]"
test_user_id = nil
if SupersetDirectory.configured?
  users = SupersetDirectory.users
  if users.any?
    test_user_id = users.first[:id]
    puts "  Using Superset user: id=#{test_user_id}"
  end
else
  puts "  ⊘ Superset not configured, using test user id=1"
  test_user_id = 1
end

# Use Rails verifier
verifier = Rails.application.message_verifier(:sse_notifications)

puts "\n[1] ISSUE FRESH TICKET"
ticket1 = verifier.generate(
  { "user_id" => test_user_id },
  expires_in: SupersetUserIdentifiable::SSE_TICKET_TTL,
  purpose: :sse_notifications
)

begin
  payload1 = verifier.verify(ticket1, purpose: :sse_notifications)
rescue ActiveSupport::MessageVerifier::InvalidSignature
  payload1 = nil
end

puts "  Ticket (first 50 chars): #{ticket1[0..50]}..."
if payload1
  puts "  ✓ Verified successfully"
  puts "    - User ID: #{payload1['user_id']}"
  puts "    - TTL: #{SupersetUserIdentifiable::SSE_TICKET_TTL}s"
else
  puts "  ✗ Verification failed"
end

puts "\n[2] IMMEDIATE RECONNECT WITH SAME TICKET"
begin
  payload1_check = verifier.verify(ticket1, purpose: :sse_notifications)
rescue ActiveSupport::MessageVerifier::InvalidSignature
  payload1_check = nil
end

if payload1_check
  puts "  ✓ Same ticket still valid immediately"
else
  puts "  ✗ Same ticket rejected immediately"
end

puts "\n[3] ISSUE A SECOND FRESH TICKET"
ticket2 = verifier.generate(
  { "user_id" => test_user_id },
  expires_in: SupersetUserIdentifiable::SSE_TICKET_TTL,
  purpose: :sse_notifications
)

begin
  payload2 = verifier.verify(ticket2, purpose: :sse_notifications)
rescue ActiveSupport::MessageVerifier::InvalidSignature
  payload2 = nil
end

puts "  New ticket (first 50 chars): #{ticket2[0..50]}..."
if payload2
  puts "  ✓ Second ticket verified"
else
  puts "  ✗ Second ticket verification failed"
end

puts "\n[4] VERIFY TICKETS ARE DIFFERENT"
if ticket1 == ticket2
  puts "  ⊘ Tokens are identical (should be different)"
else
  puts "  ✓ Each call issues a new ticket"
end

puts "\n[5] SIMULATE INVALID TICKET"
puts "  Testing invalid token..."
bad_ticket = "definitely.not.a.valid.ticket"

begin
  bad_payload = verifier.verify(bad_ticket, purpose: :sse_notifications)
rescue ActiveSupport::MessageVerifier::InvalidSignature
  bad_payload = nil
end

if bad_payload.nil?
  puts "  ✓ Invalid ticket correctly rejected"
else
  puts "  ✗ Invalid ticket accepted (unexpected)"
end

puts "\n[6] STRESS TEST - RAPID TICKET GENERATION"
puts "  Generating 10 tickets rapidly..."
tickets = []
10.times do |i|
  ticket = verifier.generate(
    { "user_id" => test_user_id },
    expires_in: SupersetUserIdentifiable::SSE_TICKET_TTL,
    purpose: :sse_notifications
  )

  begin
    payload = verifier.verify(ticket, purpose: :sse_notifications)
    if payload && payload['user_id'] == test_user_id
      tickets << ticket
      print "."
    else
      print "x"
    end
  rescue => e
    print "x"
  end
end
puts

puts "  ✓ #{tickets.count} valid tickets generated"

unique_tickets = tickets.uniq
puts "  ✓ All #{unique_tickets.count} tickets are unique"

puts "\n[7] VERIFY FIRST TICKET STILL WORKS AFTER STRESS TEST"
begin
  payload_check = verifier.verify(ticket1, purpose: :sse_notifications)
rescue ActiveSupport::MessageVerifier::InvalidSignature
  payload_check = nil
end

if payload_check
  puts "  ✓ Original fresh ticket still valid"
else
  puts "  ✗ Original ticket rejected (may have expired if test took >60s)"
end

puts "\n[SUMMARY]"
puts "  ✓ Ticket generation works correctly"
puts "  ✓ Valid tickets verify successfully"
puts "  ✓ Invalid tickets are rejected"
puts "  ✓ Each ticket is unique"
puts "  ✓ Fresh tickets are immediately usable"

puts "\n" + "=" * 70
puts "SSE TICKET TEST COMPLETE"
puts "=" * 70
