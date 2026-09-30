'use strict';
// POST /api/summarize  { transcript }  ->  { title, summary, points[], actions[{text, owner?}], topics[{name, relatedPoints[]}], links[{from, to, label}] }
// Keys come from the GEMINI_KEYS environment variable (comma-separated) and never reach the client.
module.exports = require('./_lib/core').makeHandler();
