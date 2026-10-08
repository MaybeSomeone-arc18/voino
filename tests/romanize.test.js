const test = require('node:test');
const assert = require('node:assert');
const { romanize } = require('../web/romanize.js');

test('romanizes common Hinglish phrases', () => {
  assert.strictEqual(romanize('मुझे रिपोर्ट भेजना है'), 'mujhe riport bhejna hai');
  assert.strictEqual(romanize('कल तक असाइनमेंट जमा करना है।'), 'kal tak asainment jama karna hai.');
  assert.strictEqual(romanize('हम समझना चाहते हैं'), 'hum samajhna chahte hain');
});

test('leaves English text untouched', () => {
  assert.strictEqual(romanize('We need to send the report.'), 'We need to send the report.');
});
