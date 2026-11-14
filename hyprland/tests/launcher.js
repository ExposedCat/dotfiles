// Exercise the exact JS helpers imported by QML without starting a desktop.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const folder = path.join(__dirname, '../config/shell/lib');
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(folder, 'calc.js'), 'utf8'), context);
for (const [expression, value] of [['12*(3+4)', 84], ['-2^2', -4], ['2^-2', 0.25], ['2^3^2', 512], ['50%', 0.5], ['0.1+0.2', 0.3]]) {
  const result = context.evaluate(expression);
  assert.equal(result.ok, true, expression);
  assert.equal(result.value, value, expression);
}
for (const expression of ['1/0', '42', 'python3', 'process.exit()', '2 +', '(2+3', '2**3', '1;while(true){}']) {
  assert.equal(context.evaluate(expression).ok, false, expression);
}
const fuzzy = require(path.join(folder, 'fuzzy.js'));
const apps = [{id: 'term', name: 'Terminal', description: 'Command line'}, {id: 'chat', name: 'Telegram', description: 'Messaging'}];
assert.equal(fuzzy.rank(apps, 'trm', {})[0].id, 'term');
assert.equal(fuzzy.rank(apps, 'messaging', {})[0].id, 'chat');
assert.equal(fuzzy.rank(apps, '', {chat: 10})[0].id, 'chat');
assert.equal(fuzzy.rank(apps, 'no-such-app', {}).length, 0);
console.log('Launcher fuzzy search, usage ranking, arithmetic, precedence, and invalid input passed');
