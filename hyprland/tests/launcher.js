// Exercise the exact JS helpers imported by QML without starting a desktop.
const assert = require('node:assert/strict');
const path = require('node:path');
const folder = path.join(__dirname, '../config/shell/lib');
const fuzzy = require(path.join(folder, 'fuzzy.js'));
const apps = [{id: 'term', name: 'Terminal', description: 'Command line'}, {id: 'chat', name: 'Telegram', description: 'Messaging'}];
assert.equal(fuzzy.rank(apps, 'trm', {})[0].id, 'term');
assert.equal(fuzzy.rank(apps, 'messaging', {})[0].id, 'chat');
assert.equal(fuzzy.rank(apps, '', {chat: 10})[0].id, 'chat');
assert.equal(fuzzy.rank(apps, 'no-such-app', {}).length, 0);
const titles = [
  {id: 'dev', name: 'Dev', description: 'Telephone tools'},
  {id: 'telephone', name: 'Telephone', description: ''},
  {id: 'telegram', name: 'Telegram', description: ''},
];
assert.equal(fuzzy.rank(titles, 'tele', {dev: 1000})[0].id, 'telegram');
assert.equal(fuzzy.rank(titles, 'tele', {dev: 1000})[2].id, 'dev');
assert.equal(fuzzy.titleScore(titles[0], 'tele'), 99);
assert.equal(fuzzy.titleScore(titles[2], 'еуду'), 0.1);
console.log('Launcher fuzzy search, title preference, layout recovery, and usage ranking passed');
