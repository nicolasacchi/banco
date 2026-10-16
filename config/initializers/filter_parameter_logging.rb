# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # The student's answers and the teacher's free text, and the bodies the agent submits
  # (items with keys and solutions, grades, reviews, graphs, blueprints), and the app events' payloads (they keep a refused answer, D-298), must not reach the
  # request log (D-069); `q` is the student's search words (D-299: never stored, never logged); `response` is a lesson check's answer (R3, A9: student data). Exact names, at any depth, so ids such as item_id stay readable.
  /(\A|\.)(raw|reason_it|comment_it|text|answer|item|grade|review|solve|graph|blueprint|body|blueprint_json|body_json|payload_json|text_it|note_it|final_it|files|lesson|topic|course|checklist|findings|response|q)\z/
]
