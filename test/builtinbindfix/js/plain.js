function jsMapGet(key) { const table = new Map(); return table.get(key); }
function jsArrayPush(item) { const list = []; list.push(item); return list; }
module.exports = { jsMapGet, jsArrayPush };
