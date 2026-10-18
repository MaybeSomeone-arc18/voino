'use strict';
// POST /api/vaani-dispatch  { consent, note }  ->  { token, room_name, connection_url, live_captions_url, sent_fields, prompt_chars }
// consent: { per_session: true, third_party_voice_service: true, fields: ["title","points","actions"] }
// The Vaani key comes from the VAANI_API_KEY environment variable and never reaches the client.
// Only consented note fields are sent to Vaani (a third-party voice service). The raw transcript never leaves the server request path.
module.exports = require('./_lib/vaani').makeHandler();
